//
//  TandemPumpManager+History.swift
//  TandemKit
//
//  History-fetch slice. Fetches pump history, LOGS it (raw entries + the mapped DoseEntries),
//  and emits *pump-UI* boluses (Quick Bolus / Control-IQ) to DoseStore — Part B.
//
//  A pump-UI bolus is one the driver never commanded, so it has NO optimistic counterpart in
//  DoseStore; emitting it can't double-count a commanded dose, and it closes the over-delivery
//  gap where pump-initiated insulin was invisible to the loop. Everything else — commanded
//  boluses, temp basals, suspend/resume, `lastReconciliation`, and reconciliation of the
//  optimistic doses — is handled by later steps and is NOT emitted here.
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

    /// Fetch pump history, log it, and emit pump-UI boluses (see `processFetchedHistory`).
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

        // Mark when commanded-id tracking began (first run only). Pump-UI emission is gated to
        // doses at/after this instant so boluses that predate tracking can't be double-counted.
        if state.commandedTrackingStartedAt == nil {
            state.commandedTrackingStartedAt = Date()
            notifyDelegateStateUpdated()
            historyLogger.info("[HISTORY-EMIT] began commanded-bolus tracking at \(state.commandedTrackingStartedAt!); only pump-UI boluses at/after this time are emitted")
        }

        // Resume from the persisted fetched-ranges cursor: the first run (no ranges) does a deep,
        // DIA-bounded fetch; later runs resume incrementally from just after the newest fetched
        // sequence, so we don't redundantly re-deep-fetch every launch.
        let rangeTracker = HistoryRangeTracker(fetchedRanges: state.historyFetchedRanges)
        let newestFetched = state.historyFetchedRanges.map(\.end).max()
        let isInitialSync = newestFetched == nil
        let startSequence: UInt32? = newestFetched.map { $0 &+ 1 }
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
            processFetchedHistory(logs)
            // Record the (contiguous) fetched span and persist so the next run resumes from here.
            if let minSeq = logs.map(\.sequenceNum).min(),
               let maxSeq = logs.map(\.sequenceNum).max()
            {
                rangeTracker.recordFetched(start: minSeq, end: maxSeq)
                state.historyFetchedRanges = rangeTracker.export()
                notifyDelegateStateUpdated()
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

    /// Log the fetched history (raw + mapped doses) and emit the completed pump-UI boluses.
    private func processFetchedHistory(_ logs: [HistoryLog]) {
        guard !logs.isEmpty else {
            historyLogger.info("[HISTORY-RO] no new history entries")
            return
        }

        let seqs = logs.map(\.sequenceNum)
        historyLogger.info(
            "[HISTORY-RO] fetched \(logs.count) entries, seq \(seqs.min() ?? 0)...\(seqs.max() ?? 0) — logging all, emitting pump-UI boluses only"
        )

        // Raw entries (debug level so they can be filtered out).
        for log in logs {
            historyLogger.debug("[HISTORY-RO] raw seq=\(log.sequenceNum) typeId=\(log.typeId) time=\(Dates.fromJan12008EpochSecondsToDate(TimeInterval(log.pumpTimeSec))) \(log)")
        }

        // Map history to doses. Every mapped dose is logged; only completed pump-UI boluses are
        // emitted below (see the emit block at the end of this method).
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

        emitPumpUIBoluses(events)
    }

    /// Emit ONLY completed pump-UI boluses (Quick Bolus / Control-IQ) to DoseStore.
    ///
    /// Safety rationale:
    /// - **No double-count:** a pump-UI bolus was never commanded through the driver, so it has no
    ///   optimistic counterpart in DoseStore. Commanded boluses are deliberately excluded here —
    ///   the optimistic path already owns them (reconciling those is a later step).
    /// - **Completed only:** we require `deliveredUnits != nil` (i.e. a `BolusCompleted` was seen).
    ///   An in-flight pump-UI bolus is skipped and picked up once its completion arrives in a later
    ///   fetch, so we never emit a mutable/uncertain amount here.
    /// - **`replacePendingEvents: false`:** never purge the optimistic mutable doses.
    /// - **Idempotent:** `NewPumpEvent` sets `syncIdentifier` to the entry's stable raw hex, so
    ///   re-reading the same bolus across deep fetches upserts rather than duplicates.
    /// - **Tracking cutoff:** only doses at/after `commandedTrackingStartedAt` are emitted; earlier
    ///   ones can't be reliably classified (an untracked commanded bolus would look pump-UI) so we
    ///   skip them to avoid double-counting the optimistic path.
    private func emitPumpUIBoluses(_ events: [NewPumpEvent]) {
        let cutoff = state.commandedTrackingStartedAt ?? .distantFuture
        let completedPumpUI = events.filter { event in
            guard let dose = event.dose else { return false }
            return dose.type == .bolus && dose.wasProgrammedByPumpUI && dose.deliveredUnits != nil
        }
        let pumpUIBolusEvents = completedPumpUI.filter { ($0.dose?.startDate ?? .distantPast) >= cutoff }

        let skipped = completedPumpUI.count - pumpUIBolusEvents.count
        if skipped > 0 {
            historyLogger.debug("[HISTORY-EMIT] skipped \(skipped) completed pump-UI bolus(es) predating tracking cutoff \(cutoff)")
        }
        guard !pumpUIBolusEvents.isEmpty else { return }

        let summary = pumpUIBolusEvents
            .compactMap(\.dose)
            .map { "\($0.deliveredUnits ?? $0.programmedUnits)U@\($0.startDate)" }
            .joined(separator: ", ")
        historyLogger.info(
            "[HISTORY-EMIT] emitting \(pumpUIBolusEvents.count) completed pump-UI bolus dose(s) to DoseStore (replacePendingEvents: false): \(summary)"
        )
        emitPumpEvents(pumpUIBolusEvents, replacePendingEvents: false)
    }
}
