import Foundation

/// Decides when and what ranges of pump history are fetched into the session `historyLogStore`,
/// driven from every `syncPumpData` pass. This layer only fetches and keeps bookkeeping — turning
/// stored logs into LoopKit dose events is a separate layer that gates on `historyEmitFloor`.
extension TandemPumpManager {
    /// Total lookback for the initial deep backfill. Bounds how far below the emit floor the walk
    /// goes when the host app's boundary is ancient (a fresh install reports `.distantPast`).
    static let historyBackfillWindow: TimeInterval = .hours(24)

    /// Margin below the emit floor covering pump/app clock skew, so an event stamped right at
    /// the boundary isn't clipped.
    static let historyBackfillFloorMargin: TimeInterval = .minutes(1)

    /// The IOB-relevant lookback (≈ insulin action duration). On first connect the doses in this
    /// window are what IOB is computed from, so the deep backfill covers it in a single
    /// uninterrupted pass — the per-sync window cap below only applies to history older than
    /// this.
    static let historyBackfillPriorityWindow: TimeInterval = .hours(6)

    /// Entries per backfill step. 255 is the most a single HistoryLogRequest can carry, so one
    /// step costs exactly one chunk round-trip.
    static let historyBackfillWindowEntries = 255

    /// Cap on backward windows per sync pass, applied only once the walk has cleared the
    /// priority window — the IOB-relevant hours are never paced, only the background tail out to
    /// the full lookback. Keeps one sync from monopolizing BLE on a chatty pump; the walk
    /// resumes on the next sync.
    static let historyBackfillMaxWindowsPerSync = 8

    /// Most entries an incremental catch-up requests in one pass.
    static let historyIncrementalBackstop = 500

    /// Seeds `state.historyEmitFloor` from the host app's dose-history boundary, exactly once.
    /// Returns whether a floor is established (pre-existing or just seeded).
    @discardableResult
    func establishHistoryEmitFloorIfNeeded() -> Bool {
        guard state.historyEmitFloor == nil else {
            return true
        }
        guard let delegate = pumpManagerDelegate else {
            // On a fresh pump add the first sync can run before the host app wires the delegate.
            // Do NOT fall back to `now` — that reproduces exactly the re-pair-time floor this
            // seed exists to avoid (the whole disconnected-gap backfill would be skipped).
            // Defer and retry next sync; emits also no-op without a delegate, so the boundary
            // doesn't advance meanwhile.
            logger.warning("[HISTORY-BACKFILL] No delegate to read the emit floor from yet; deferring")
            return false
        }

        let floor = delegate.startDateToFilterNewPumpEvents(for: self)
        state.historyEmitFloor = floor
        notifyDelegateStateUpdated()
        logger.info("[HISTORY-BACKFILL] Seeded emit floor from host app: \(floor)")
        return true
    }

    /// Sync-cycle entry point. While the deep backfill has not completed, continues it; afterwards
    /// catches up incrementally from the persisted watermark. Fire-and-forget: window completions
    /// arrive on the main queue and the pass releases itself when done or on the first failure.
    func backfillHistoryIfNeeded(now: Date = Date()) {
        guard historyLogStoreSerial != nil else {
            logger.info("[HISTORY-BACKFILL] Skipping: pump serial not yet known")
            return
        }
        guard let emitFloor = state.historyEmitFloor else {
            // The floor is seeded at the top of the sync; if it could not be (no delegate yet),
            // skip this cycle rather than backfill against an unknown boundary.
            logger.info("[HISTORY-BACKFILL] Skipping: emit floor not yet seeded")
            return
        }

        historyBackfillLock.lock()
        if historyBackfillInFlight {
            historyBackfillLock.unlock()
            logger.info("[HISTORY-BACKFILL] Skipping: a pass is already in flight")
            return
        }
        historyBackfillInFlight = true
        historyBackfillWindowsThisPass = 0
        historyBackfillLock.unlock()

        if state.historyBackfillCompletedAt == nil {
            continueDeepBackfill(emitFloor: emitFloor, now: now)
        } else {
            performIncrementalFetch()
        }
    }

    // MARK: - Deep backfill

    /// One pass of the initial deep backfill: walks backward from the store's oldest entry (or
    /// the pump's newest, when the store is empty) one fetcher window at a time until the target
    /// date is reached, the pump runs out of history, or the per-pass window cap is hit. While
    /// `historyBackfillCompletedAt` stays nil every sync re-enters here, so an interrupted walk
    /// resumes instead of being stranded.
    private func continueDeepBackfill(emitFloor: Date, now: Date) {
        // Margin below the floor for clock skew; the fixed window bounds a floor far in the past.
        let target = max(
            emitFloor.addingTimeInterval(-Self.historyBackfillFloorMargin),
            now.addingTimeInterval(-Self.historyBackfillWindow)
        )
        // Everything newer than this feeds IOB; the window cap holds off until the walk clears it.
        let priorityBoundary = max(target, now.addingTimeInterval(-Self.historyBackfillPriorityWindow))
        logger.info("[HISTORY-BACKFILL] Continuing deep backfill toward \(target)")
        deepBackfillStep(target: target, priorityBoundary: priorityBoundary, now: now)
    }

    private func deepBackfillStep(target: Date, priorityBoundary: Date, now: Date) {
        guard let serial = historyLogStoreSerial else {
            finishBackfillPass()
            return
        }

        // Resume below the oldest stored entry. After a relaunch the store is empty, so the walk
        // restarts from the pump's newest (endingAt = nil) — re-fetching what an earlier run
        // already emitted is safe because dose identifiers make re-reports idempotent.
        let frontierBefore: UInt32?
        do {
            frontierBefore = try historyLogStore.oldest(pumpSerial: serial.rawValue)?.sequenceNum
        } catch {
            logger.error("[HISTORY-BACKFILL] Could not read the store frontier: \(error)")
            finishBackfillPass()
            return
        }
        if let frontierBefore, frontierBefore == 0 {
            completeDeepBackfill(at: now, reason: "reached sequence number 0")
            return
        }
        let endingAt = frontierBefore.map { $0 - 1 }

        historyBackfillFetcher.start(
            numberOfLogs: Self.historyBackfillWindowEntries,
            endingAtSequenceNum: endingAt
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .failure(error):
                // Left incomplete: the next sync re-enters the deep backfill and resumes from
                // the store's frontier.
                self.logger.error("[HISTORY-BACKFILL] Window fetch failed: \(error)")
                self.finishBackfillPass()
            case let .success(progress):
                self.handleDeepBackfillWindow(
                    progress: progress,
                    frontierBefore: frontierBefore,
                    target: target,
                    priorityBoundary: priorityBoundary,
                    now: now
                )
            }
        }
    }

    private func handleDeepBackfillWindow(
        progress: HistoryLogFetcher.Progress,
        frontierBefore: UInt32?,
        target: Date,
        priorityBoundary: Date,
        now: Date
    ) {
        guard let serial = historyLogStoreSerial else {
            finishBackfillPass()
            return
        }

        updateHistoryWatermarkFromStore(serial: serial)

        // Entries seeded from the store count as fetched in Progress, so zero here genuinely
        // means the pump had nothing in the window.
        if progress.fetchedCount == 0 || progress.expectedCount == 0 {
            completeDeepBackfill(at: now, reason: "pump has no entries in the window")
            return
        }

        let oldest = try? historyLogStore.oldest(pumpSerial: serial.rawValue)

        // The fetcher clamps its window into the pump's [first, last] range, so a step below the
        // pump's first sequence number folds back onto stored territory and makes no downward
        // progress — that, not an empty window, is how reaching the start of pump history looks.
        if let frontierBefore, let frontierAfter = oldest?.sequenceNum, frontierAfter >= frontierBefore {
            completeDeepBackfill(at: now, reason: "reached the start of pump history")
            return
        }

        if let oldestDate = oldest?.pumpDate, oldestDate <= target {
            completeDeepBackfill(at: now, reason: "reached target date \(target)")
            return
        }

        historyBackfillLock.lock()
        historyBackfillWindowsThisPass += 1
        let windows = historyBackfillWindowsThisPass
        historyBackfillLock.unlock()

        // The cap never interrupts the IOB-relevant window: until the walk's oldest entry clears
        // the priority boundary, a pass keeps going regardless of how many windows a chatty pump
        // takes to cover those hours. Only the background tail is paced across syncs.
        let priorityCovered = oldest.map { $0.pumpDate <= priorityBoundary } ?? false
        if priorityCovered, windows >= Self.historyBackfillMaxWindowsPerSync {
            // Left incomplete on purpose: `historyBackfillCompletedAt` stays nil, so the next
            // sync resumes the walk from the store's new frontier.
            logger.info("[HISTORY-BACKFILL] Window cap (\(windows)) reached; resuming next sync")
            finishBackfillPass()
            return
        }

        deepBackfillStep(target: target, priorityBoundary: priorityBoundary, now: now)
    }

    private func completeDeepBackfill(at now: Date, reason: String) {
        state.historyBackfillCompletedAt = now
        notifyDelegateStateUpdated()
        logger.info("[HISTORY-BACKFILL] Deep backfill complete: \(reason)")
        finishBackfillPass()
    }

    // MARK: - Incremental catch-up

    /// Fetches [watermark + 1, pump newest], bounded by `historyIncrementalBackstop`.
    private func performIncrementalFetch() {
        guard let watermark = state.historyLastFetchedSequenceNum else {
            // Completed-but-no-watermark should not normally occur; fetch one window ending at
            // the pump's newest so the watermark re-establishes itself.
            logger.warning("[HISTORY-BACKFILL] No watermark despite completed backfill; fetching one window")
            startIncrementalFetch(numberOfLogs: Self.historyBackfillWindowEntries)
            return
        }

        historyBackfillFetcher.fetchStatus { [weak self] status in
            guard let self else { return }
            guard let status else {
                self.logger.warning("[HISTORY-BACKFILL] No history log status; skipping incremental fetch")
                self.finishBackfillPass()
                return
            }

            if watermark > status.lastSequenceNum {
                // The pump's history restarted below the watermark (history reset, or replaced
                // hardware reusing this state): the bookkeeping no longer describes this pump's
                // history, so drop it and let the next sync re-run the deep backfill.
                self.logger.warning(
                    "[HISTORY-BACKFILL] Watermark \(watermark) is above pump last " +
                        "\(status.lastSequenceNum); resetting for a fresh deep backfill"
                )
                self.state.historyLastFetchedSequenceNum = nil
                self.state.historyBackfillCompletedAt = nil
                self.notifyDelegateStateUpdated()
                self.finishBackfillPass()
                return
            }

            guard status.lastSequenceNum > watermark else {
                self.finishBackfillPass()
                return
            }

            let count = min(Int(status.lastSequenceNum - watermark), Self.historyIncrementalBackstop)
            self.logger.info("[HISTORY-BACKFILL] Incremental fetch of \(count) entries above \(watermark)")
            self.startIncrementalFetch(numberOfLogs: count)
        }
    }

    private func startIncrementalFetch(numberOfLogs: Int) {
        historyBackfillFetcher.start(numberOfLogs: numberOfLogs) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .failure(error):
                self.logger.error("[HISTORY-BACKFILL] Incremental fetch failed: \(error)")
            case .success:
                if let serial = self.historyLogStoreSerial {
                    self.updateHistoryWatermarkFromStore(serial: serial)
                }
            }
            self.finishBackfillPass()
        }
    }

    // MARK: - Bookkeeping

    /// Advances `state.historyLastFetchedSequenceNum` to the store's newest entry, so an
    /// incremental fetch after a relaunch resumes where this session left off.
    private func updateHistoryWatermarkFromStore(serial: HistoryLogSyncIdentifier.PumpSerial) {
        guard let newest = try? historyLogStore.newest(pumpSerial: serial.rawValue) else {
            return
        }
        let advanced = max(state.historyLastFetchedSequenceNum ?? 0, newest.sequenceNum)
        if advanced != state.historyLastFetchedSequenceNum {
            state.historyLastFetchedSequenceNum = advanced
            notifyDelegateStateUpdated()
        }
    }

    private func finishBackfillPass() {
        historyBackfillLock.lock()
        historyBackfillInFlight = false
        historyBackfillLock.unlock()
    }
}
