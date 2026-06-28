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
    /// Most recent entries to pull on the first (cursor-less) fetch. Kept small so the live
    /// trial is fast and the logs are readable; later (IOB-emitting) work will bound by
    /// `startDateToFilterNewPumpEvents` instead.
    private var historyReadOnlyFetchLimit: Int { 50 }

    /// Routes an incoming HistoryLogStreamResponse (delivered on the CB delegate queue) to the
    /// in-flight fetch session's collector. No-op when no fetch is active.
    func handleHistoryLogStream(_ response: HistoryLogStreamResponse) {
        activeHistoryFetchSession?.handleStreamResponse(response)
    }

    /// READ-ONLY: fetch recent (or newly-arrived) pump history and log it. Never emits.
    /// Runs synchronously on the caller's (background, already-connected) queue.
    func fetchAndLogPumpHistory() {
        guard activeHistoryFetchSession == nil else {
            historyLogger.debug("[HISTORY-RO] fetch already in progress; skipping")
            return
        }

        // Incremental after the first run: only pull entries newer than the last we logged.
        let startSequence: UInt32? = lastFetchedHistorySequence.map { $0 &+ 1 }
        let session = HistoryFetchSession(
            sender: bluetooth,
            startSequence: startSequence,
            maxEntries: startSequence == nil ? historyReadOnlyFetchLimit : 200
        )

        activeHistoryFetchSession = session
        defer { activeHistoryFetchSession = nil }

        historyLogger.info("[HISTORY-RO] starting fetch (startSequence=\(startSequence.map { "\($0)" } ?? "recent"))")

        do {
            let logs = try session.fetchWithRetry()
            logFetchedHistory(logs)
            if let maxSeq = logs.map(\.sequenceNum).max() {
                lastFetchedHistorySequence = maxSeq
            }
        } catch {
            historyLogger.error("[HISTORY-RO] fetch failed: \(String(describing: error))")
        }
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
            historyLogger.debug("[HISTORY-RO] raw seq=\(log.sequenceNum) \(log)")
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
