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

    /// Initial deep-fetch lookback window (≈ insulin duration). Deliberately a *fixed* window, NOT
    /// Loop's `startDateToFilterNewPumpEvents`: that returns `pumpEventQueryAfterDate` — Loop's
    /// "newest finalized event I was told about" cursor, driven by the optimistic path, not by
    /// reconciled pump history. On a running system it's ≈ now and can sit *past* unreported pump-UI
    /// doses (e.g. a Quick Bolus), so bounding the fetch by it would miss them. The fetch must reach
    /// ≈DIA back on its own. See live_test_notes.md.
    private var historyDeepFetchWindow: TimeInterval { .hours(6) }

    /// Routes an incoming HistoryLogStreamResponse (delivered on the CB delegate queue) to the
    /// in-flight fetch session's collector. No-op when no fetch is active.
    func handleHistoryLogStream(_ response: HistoryLogStreamResponse) {
        activeHistoryFetchSession?.handleStreamResponse(response)
    }

    /// READ-ONLY: fetch pump history and log it. Never emits.
    /// - **Initial sync** (no cursor — also after an app restart / overnight power-down): a *deep*
    ///   fetch bounded by a fixed ≈insulin-duration window (see `historyDeepFetchWindow`), with a
    ///   metrics line.
    /// - **Subsequent cycles:** a small incremental fetch of entries newer than the last we logged.
    /// Runs synchronously on the caller's (background, already-connected) queue.
    func fetchAndLogPumpHistory() {
        guard activeHistoryFetchSession == nil else {
            historyLogger.debug("[HISTORY-RO] fetch already in progress; skipping")
            return
        }

        let isInitialSync = lastFetchedHistorySequence == nil
        let startSequence: UInt32? = lastFetchedHistorySequence.map { $0 &+ 1 }
        // Fixed ≈DIA window (see historyDeepFetchWindow): the fetch must reach DIA back on its own,
        // independent of Loop's startDateToFilterNewPumpEvents (an optimistic cursor, not history).
        let stopBeforeDate: Date? = isInitialSync ? Date().addingTimeInterval(-historyDeepFetchWindow) : nil
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
            roundBasalRate: { self.roundToSupportedBasalRate(unitsPerHour: $0) },
            isCommandedBolus: { self.state.isCommandedBolus(id: $0) }
        )

        let bolusDoses = events.compactMap(\.dose).filter { $0.type == .bolus }
        let pumpUIBoluses = bolusDoses.filter(\.wasProgrammedByPumpUI).count
        historyLogger.info(
            "[HISTORY-RO] mapped \(events.count) dose event(s) (logged only); boluses: \(bolusDoses.count) (\(pumpUIBoluses) pump-UI, \(bolusDoses.count - pumpUIBoluses) commanded):"
        )
        for event in events {
            if let dose = event.dose {
                let delivered = dose.deliveredUnits.map { "\($0)" } ?? "-"
                // For boluses, classify app-commanded vs pump-UI (Quick Bolus / Control-IQ) from the
                // bolusId join. Read-only: this only annotates the log; nothing is emitted.
                let source = dose.type == .bolus ? (dose.wasProgrammedByPumpUI ? " source=PUMP-UI" : " source=COMMANDED") : ""
                historyLogger.info(
                    "[HISTORY-RO] dose type=\(dose.type) start=\(dose.startDate) end=\(dose.endDate) programmedUnits=\(dose.programmedUnits) unitsPerHour=\(dose.unitsPerHour) \(dose.unit) delivered=\(delivered)\(source) sync=\(dose.syncIdentifier ?? "-")"
                )
            } else {
                let typeStr = event.type.map { "\($0)" } ?? "-"
                historyLogger.info("[HISTORY-RO] event type=\(typeStr) title=\(event.title) (no dose)")
            }
        }
    }
}
