//
//  TandemPumpManager+History.swift
//  TandemKit
//
//  READ-ONLY history-fetch slice. Fetches pump history and LOGS it (raw entries + the
//  DoseEntries the mapper would produce) so the fetch, parsing, and the dose-mapping fixes
//  can be validated on a live pump. Nothing here calls `hasNewPumpEvents` / emits to
//  DoseStore, so IOB and dosing are completely unaffected. The emit + reconcile path is a
//  later, separate step.
//

import Foundation
import LoopKit

extension TandemPumpManager {
    /// Hard backstop on the initial (DIA-bounded) deep fetch. The date bound should stop us well
    /// before this; if we hit it, the bound isn't working and the summary line flags it.
    private var historyDeepFetchBackstop: Int { 1000 }

    /// Fallback deep-fetch lookback window (≈ insulin duration), used only if there's no delegate to
    /// provide Loop's `startDateToFilterNewPumpEvents`.
    private var historyDeepFetchWindow: TimeInterval { .hours(6) }

    /// Routes an incoming HistoryLogStreamResponse (delivered on the CB delegate queue) to the
    /// in-flight fetch session's collector. No-op when no fetch is active.
    func handleHistoryLogStream(_ response: HistoryLogStreamResponse) {
        activeHistoryFetchSession?.handleStreamResponse(response)
    }

    /// READ-ONLY: fetch pump history and log it. Never emits.
    /// - **Initial sync** (no cursor — also after an app restart / overnight power-down): a *deep*
    ///   fetch bounded by Loop's `startDateToFilterNewPumpEvents` (≈ insulin duration), read on the
    ///   delegate queue via `pumpDelegate.call`, with a metrics line.
    /// - **Subsequent cycles:** a small incremental fetch of entries newer than the last we logged.
    /// Runs synchronously on the caller's (background, already-connected) queue.
    func fetchAndLogPumpHistory() {
        guard activeHistoryFetchSession == nil else {
            historyLogger.debug("[HISTORY-RO] fetch already in progress; skipping")
            return
        }

        let isInitialSync = lastFetchedHistorySequence == nil
        let startSequence: UInt32? = lastFetchedHistorySequence.map { $0 &+ 1 }
        // Real DIA bound from Loop, read ON the delegate queue via `pumpDelegate.call` — calling the
        // delegate directly off-queue traps a `dispatchPrecondition` (EXC_BREAKPOINT). Falls back to
        // a fixed window if there's no delegate yet. The extra −1 min is MinimedKit's slop for
        // pump/app clock skew, so we don't clip an event right at the boundary.
        let stopBeforeDate: Date?
        if isInitialSync {
            let loopFilterDate = pumpDelegate.call { delegate in
                delegate?.startDateToFilterNewPumpEvents(for: self)
            }
            stopBeforeDate = (loopFilterDate ?? Date().addingTimeInterval(-historyDeepFetchWindow))
                .addingTimeInterval(-.minutes(1))
        } else {
            stopBeforeDate = nil
        }
        let maxEntries = isInitialSync ? historyDeepFetchBackstop : 200

        let session = HistoryFetchSession(
            sender: bluetooth,
            startSequence: startSequence,
            maxEntries: maxEntries,
            stopBeforeDate: stopBeforeDate
        )
        activeHistoryFetchSession = session
        defer { activeHistoryFetchSession = nil }

        let kind = isInitialSync ? "DEEP (DIA-bounded)" : "incremental"
        historyLogger.info(
            "[HISTORY-RO] starting \(kind) fetch (startSequence=\(startSequence.map { "\($0)" } ?? "recent"), stopBefore=\(stopBeforeDate.map { "\($0)" } ?? "none"), backstop=\(maxEntries))"
        )

        let started = Date()
        do {
            let logs = try session.fetchWithRetry()
            let elapsed = Date().timeIntervalSince(started)
            if isInitialSync {
                logDeepFetchSummary(logs, elapsed: elapsed, stopBeforeDate: stopBeforeDate, backstop: maxEntries)
            }
            logFetchedHistory(logs)
            if let maxSeq = logs.map(\.sequenceNum).max() {
                lastFetchedHistorySequence = maxSeq
            }
        } catch {
            let elapsed = Date().timeIntervalSince(started)
            historyLogger.error("[HISTORY-RO] \(kind) fetch FAILED after \(String(format: "%.1f", elapsed))s: \(String(describing: error))")
        }
    }

    /// One-line metrics for the deep fetch: timing / count / sequence range / how far back we
    /// reached / what stopped us (DIA bound vs backstop).
    private func logDeepFetchSummary(_ logs: [HistoryLog], elapsed: TimeInterval, stopBeforeDate: Date?, backstop: Int) {
        let seqs = logs.map(\.sequenceNum)
        let oldest = logs.map { Dates.fromJan12008EpochSecondsToDate(TimeInterval($0.pumpTimeSec)) }.min()
        let reachedDIA = oldest != nil && stopBeforeDate != nil && oldest! <= stopBeforeDate!
        let hitBackstop = logs.count >= backstop
        historyLogger.info(
            "[HISTORY-RO] DEEP fetch done: \(logs.count) entries in \(String(format: "%.1f", elapsed))s, seq \(seqs.min() ?? 0)...\(seqs.max() ?? 0), oldest=\(oldest.map { "\($0)" } ?? "-"), DIA target=\(stopBeforeDate.map { "\($0)" } ?? "-"), reachedDIA=\(reachedDIA), hitBackstop=\(hitBackstop)"
        )
    }

    private func logFetchedHistory(_ logs: [HistoryLog]) {
        guard !logs.isEmpty else {
            historyLogger.info("[HISTORY-RO] no new history entries")
            return
        }

        let seqs = logs.map(\.sequenceNum)
        historyLogger.info(
            "[HISTORY-RO] fetched \(logs.count) entries, seq \(seqs.min() ?? 0)...\(seqs.max() ?? 0) — NOT emitting to DoseStore"
        )

        // Raw entries (debug level so they can be filtered out).
        for log in logs {
            historyLogger.debug("[HISTORY-RO] raw seq=\(log.sequenceNum) typeId=\(log.typeId) time=\(Dates.fromJan12008EpochSecondsToDate(TimeInterval(log.pumpTimeSec))) \(log)")
        }

        // Run the mapper to validate the fixes (temp-basal absolute rate, timestamps,
        // suspend/resume) against real data. These DoseEntries are logged only, never emitted.
        let reconciler = HistoryTimestampReconciler()
        let events = HistoryToDoseMapper().mapToEvents(
            logs,
            reconciler: reconciler,
            insulinType: state.insulinType,
            timeZone: .current,
            scheduledBasalRate: { self.getScheduledBasalRate(at: $0) },
            roundBasalRate: { self.roundToSupportedBasalRate(unitsPerHour: $0) }
        )

        historyLogger.info("[HISTORY-RO] mapped \(events.count) dose event(s) (logged only):")
        for event in events {
            if let dose = event.dose {
                let delivered = dose.deliveredUnits.map { "\($0)" } ?? "-"
                historyLogger.info(
                    "[HISTORY-RO] dose type=\(dose.type) start=\(dose.startDate) end=\(dose.endDate) programmedUnits=\(dose.programmedUnits) unitsPerHour=\(dose.unitsPerHour) \(dose.unit) delivered=\(delivered) sync=\(dose.syncIdentifier ?? "-")"
                )
            } else {
                let typeStr = event.type.map { "\($0)" } ?? "-"
                historyLogger.info("[HISTORY-RO] event type=\(typeStr) title=\(event.title) (no dose)")
            }
        }
    }
}
