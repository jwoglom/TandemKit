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
    /// Entries fetched per cooperative deep-fetch step. Each step is one command-queue job that holds
    /// the queue only for its own chunk (~this many entries at ~50 ms each), then yields so therapy
    /// commands and real-time incremental fetches run before the next step. Keep small for prompt
    /// bolus detection during a long backfill.
    private var historyDeepStepEntries: Int { 32 }

    /// Safety cap on cooperative deep-fetch steps (prevents an unbounded backward walk if the date
    /// bound is never reached). 400 × 32 ≈ 12.8k entries — comfortably past any realistic DIA window.
    private var historyDeepMaxSteps: Int { 400 }

    /// Initial deep-fetch lookback window (≈ insulin duration). Deliberately a *fixed* window, NOT
    /// Loop's `startDateToFilterNewPumpEvents`: that returns `pumpEventQueryAfterDate` — Loop's
    /// "newest finalized event I was told about" cursor, driven by the optimistic path, not by
    /// reconciled pump history. On a running system it's ≈ now and can sit *past* unreported pump-UI
    /// doses (e.g. a Quick Bolus), so bounding the fetch by it would miss them. The fetch must reach
    /// ≈DIA back on its own. See live_test_notes.md.
    private var historyDeepFetchWindow: TimeInterval { .hours(6) }

    /// Total lookback for the initial cooperative backfill. Phase 1 covers `historyDeepFetchWindow`
    /// (≈DIA, IOB-relevant); phase 2 continues in the background to this depth to give retrospective
    /// analysis (therapy-setting tuning) a fuller picture. Purely a fetch/log depth — the older data
    /// only reaches DoseStore once the full emit lands (Part D). 24h ≈ 68 steps at ~90 entries/hr.
    private var historyBackfillWindow: TimeInterval { .hours(24) }

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
        // Mark when commanded-id tracking began (first run only). Pump-UI emission is gated to
        // doses at/after this instant so boluses that predate tracking can't be double-counted.
        if state.commandedTrackingStartedAt == nil {
            state.commandedTrackingStartedAt = Date()
            notifyDelegateStateUpdated()
            historyLogger.info("[HISTORY-EMIT] began commanded-bolus tracking at \(state.commandedTrackingStartedAt!); only pump-UI boluses at/after this time are emitted")
        }

        // First run (no persisted ranges): kick off a cooperative backfill that steps backward one
        // chunk per command-queue job, yielding the queue between chunks. Two phases: phase 1 to the
        // DIA window (IOB-relevant), phase 2 continuing in the background to the 24h backfill depth.
        // Later runs resume with a small single-job incremental fetch of entries newer than the cursor.
        if state.historyFetchedRanges.isEmpty {
            guard !deepBackfillInProgress else {
                historyLogger.debug("[HISTORY-DEEP] deep fetch already in progress; skipping")
                return
            }
            let now = Date()
            startCooperativeDeepFetch(
                diaBoundary: now.addingTimeInterval(-historyDeepFetchWindow),
                backfillTarget: now.addingTimeInterval(-historyBackfillWindow)
            )
            return
        }

        performIncrementalFetch()
    }

    /// A small, single-job fetch of entries newer than the persisted cursor. Fast (usually one
    /// chunk) and runs to completion within one command-queue job. Safe to run between deep-fetch
    /// steps — this is the real-time path that keeps pump-UI bolus detection prompt.
    private func performIncrementalFetch() {
        guard activeHistoryFetchSession == nil else {
            historyLogger.debug("[HISTORY-RO] fetch already in progress; skipping")
            return
        }

        let rangeTracker = HistoryRangeTracker(fetchedRanges: state.historyFetchedRanges)
        let newestFetched = state.historyFetchedRanges.map(\.end).max()
        let startSequence: UInt32? = newestFetched.map { $0 &+ 1 }

        let session = HistoryFetchSession(sender: bluetooth, startSequence: startSequence, maxEntries: 200)
        activeHistoryFetchSession = session
        defer { activeHistoryFetchSession = nil }

        historyLogger.info(
            "[HISTORY-RO] starting incremental fetch (startSequence=\(startSequence.map { "\($0)" } ?? "recent"), backstop=200)"
        )

        do {
            let logs = try session.fetchWithRetry()
            processFetchedHistory(logs)
            if let minSeq = logs.map(\.sequenceNum).min(),
               let maxSeq = logs.map(\.sequenceNum).max()
            {
                rangeTracker.recordFetched(start: minSeq, end: maxSeq)
                state.historyFetchedRanges = rangeTracker.export()
                notifyDelegateStateUpdated()
            }
        } catch {
            historyLogger.error("[HISTORY-RO] incremental fetch FAILED: \(String(describing: error))")
        }
    }

    /// Kick off the cooperative two-phase backfill: step backward one chunk per command-queue job,
    /// re-enqueuing each next step via `ensureConnected` so any therapy command or real-time
    /// incremental fetch runs first. Phase 1 covers to `diaBoundary` (IOB-relevant); phase 2 continues
    /// in the background to `backfillTarget` (≈24h). Never holds the command queue for the whole fetch.
    private func startCooperativeDeepFetch(diaBoundary: Date, backfillTarget: Date) {
        deepBackfillInProgress = true
        historyLogger.info("[HISTORY-DEEP] starting cooperative backfill: phase 1 to DIA \(diaBoundary), phase 2 to \(backfillTarget) (yields the command queue between chunks)")
        stepDeepFetch(endingAt: nil, diaBoundary: diaBoundary, backfillTarget: backfillTarget, phase1Reached: false, stepIndex: 0)
    }

    /// One cooperative step: fetch a single chunk ending at `endingAt` (nil = pump's newest), process
    /// + emit + record it, then either finish (reached `backfillTarget` or start of history) or
    /// re-enqueue the next step one chunk further back. Logs a milestone the first time it crosses
    /// `diaBoundary` (phase 1 → phase 2), so IOB-relevant coverage is visible in the logs.
    private func stepDeepFetch(endingAt: UInt32?, diaBoundary: Date, backfillTarget: Date, phase1Reached: Bool, stepIndex: Int) {
        guard stepIndex < historyDeepMaxSteps else {
            historyLogger.warning("[HISTORY-DEEP] hit max step cap (\(historyDeepMaxSteps)); stopping backfill")
            deepBackfillInProgress = false
            return
        }

        // Each step is its own command-queue job. Re-enqueuing via ensureConnected sends the next
        // step to the back of the serial queue, so anything enqueued meanwhile (a bolus, a temp, a
        // bolusChange-triggered incremental) runs before the next chunk — that's the cooperation.
        bluetooth.ensureConnected { error in
            if let error {
                self.historyLogger.error("[HISTORY-DEEP] step \(stepIndex) connect failed: \(error.localizedDescription); aborting backfill")
                self.deepBackfillInProgress = false
                return
            }

            let session = HistoryFetchSession(
                sender: self.bluetooth,
                startSequence: nil,
                maxEntries: self.historyDeepStepEntries,
                endSequence: endingAt
            )
            self.activeHistoryFetchSession = session
            let started = Date()
            var logs: [HistoryLog] = []
            do {
                logs = try session.fetchWithRetry()
            } catch {
                self.historyLogger.error("[HISTORY-DEEP] step \(stepIndex) fetch failed: \(String(describing: error))")
            }
            self.activeHistoryFetchSession = nil
            let elapsed = Date().timeIntervalSince(started)

            guard let minSeq = logs.map(\.sequenceNum).min(),
                  let maxSeq = logs.map(\.sequenceNum).max()
            else {
                self.historyLogger.info("[HISTORY-DEEP] step \(stepIndex) returned no entries; backfill complete (reached start of history)")
                self.deepBackfillInProgress = false
                return
            }

            self.processFetchedHistory(logs)
            let tracker = HistoryRangeTracker(fetchedRanges: self.state.historyFetchedRanges)
            tracker.recordFetched(start: minSeq, end: maxSeq)
            self.state.historyFetchedRanges = tracker.export()
            self.notifyDelegateStateUpdated()

            let oldest = logs.map { Dates.fromJan12008EpochSecondsToDate(TimeInterval($0.pumpTimeSec)) }.min()!
            self.historyLogger.info("[HISTORY-DEEP] step \(stepIndex): \(logs.count) entries seq \(minSeq)...\(maxSeq) in \(String(format: "%.1f", elapsed))s, oldest=\(oldest)")

            // Phase-1 milestone: the first step whose oldest entry reaches the DIA window. IOB-relevant
            // coverage is complete here; everything further back is background retrospective data.
            var reachedPhase1 = phase1Reached
            if !reachedPhase1, oldest <= diaBoundary {
                reachedPhase1 = true
                self.historyLogger.info("[HISTORY-DEEP] phase 1 (DIA) reached at step \(stepIndex); continuing background backfill to \(backfillTarget)")
            }

            if oldest <= backfillTarget {
                self.historyLogger.info("[HISTORY-DEEP] cooperative backfill DONE at step \(stepIndex): reached target \(backfillTarget)")
                self.deepBackfillInProgress = false
                return
            }
            if minSeq == 0 {
                self.historyLogger.info("[HISTORY-DEEP] cooperative backfill DONE: reached start of pump history (seq 0)")
                self.deepBackfillInProgress = false
                return
            }

            self.stepDeepFetch(endingAt: minSeq &- 1, diaBoundary: diaBoundary, backfillTarget: backfillTarget, phase1Reached: reachedPhase1, stepIndex: stepIndex + 1)
        }
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

            // Diagnostic (info level → also written to tandem_log.txt): the basal-delivery record
            // (typeId 279) reports the effective rates in milliunits/hr and their source. Not mapped
            // to a dose; logged so we can inspect Control-IQ's algorithmRate vs profile/temp.
            if let basal = log as? BasalDeliveryHistoryLog {
                let time = Dates.fromJan12008EpochSecondsToDate(TimeInterval(log.pumpTimeSec))
                historyLogger.info("[HISTORY-BASAL279] seq=\(log.sequenceNum) time=\(time) source=\(basal.commandedRateSource) commandedRate=\(basal.commandedRate) profile=\(basal.profileBasalRate) algorithm=\(basal.algorithmRate) temp=\(basal.tempRate) (mU/hr)")
            }

            // Diagnostic (info level → tandem_log.txt): the running basal odometer (typeId 81),
            // emitted ≥ hourly and on every rate change, resetting at midnight. Diffing
            // `dailyTotalBasal` across two entries gives ACTUAL basal delivered in that interval —
            // the closest signal we have to real (pulse-quantized) basal delivery for accounting.
            if let daily = log as? DailyBasalHistoryLog {
                let time = Dates.fromJan12008EpochSecondsToDate(TimeInterval(log.pumpTimeSec))
                historyLogger.info("[HISTORY-DAILYBASAL] seq=\(log.sequenceNum) time=\(time) dailyTotalBasal=\(daily.dailyTotalBasal)U lastBasalRate=\(daily.lastBasalRate)U/hr iob=\(daily.iob)U finalEventForDay=\(daily.finalEventForDay)")
            }
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
