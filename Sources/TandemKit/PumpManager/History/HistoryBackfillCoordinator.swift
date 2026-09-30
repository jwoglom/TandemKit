import Foundation

/// Keeps the session history log store caught up with the pump, in slices small enough that
/// dosing commands never wait long behind it.
///
/// Driven from `syncPumpData`, on LoopKit's own sync cadence. Each tick asks
/// `HistoryBackfillPlanner` what to read, runs those ranges through `HistoryLogFetcher` (which
/// files what streams in into the store and serves what the store already holds), and advances
/// the persisted watermark. Each tick that read something hands its outcome to
/// `TandemPumpManager.reportHistoryDoses`, which decides what reaches the host.
final class HistoryBackfillCoordinator {
    struct TickOutcome: Equatable {
        /// Bookkeeping as persisted at the end of the tick.
        var bookkeeping: HistoryBackfillState
        /// Ranges the tick actually read, in the order they were read.
        var rangesRead: [ClosedRange<UInt32>]
        /// The span this session has read into the store, after the tick.
        var sessionCovered: ClosedRange<UInt32>?
        /// Whether the walk backward has nothing left to reach.
        var isDeepBackfillComplete: Bool
        /// Earliest date a dose may be reported for, as of this tick.
        var emitFloor: Date

        // The rest is for the diagnostics screen.
        var pumpStatus: HistoryLogStatusReading?
        var plan: HistoryBackfillPlanner.Plan?
        /// After matching against the connected pump, before any log-erase reset.
        var watermarkBefore: UInt32?
        var watermarkWasReset = false
        /// Re-derived next tick.
        var rangesFailed: [ClosedRange<UInt32>] = []
        var hitDeepSliceCap = false
    }

    private struct RunResult {
        var bookkeeping: HistoryBackfillState
        var read: [ClosedRange<UInt32>] = []
        var failed: [ClosedRange<UInt32>] = []
        var hitDeepSliceCap = false
    }

    private let logger = TandemLogger(category: "HistoryBackfill")
    // Weak, not unowned: a tick can still be unwinding on the fetcher's queue after the user
    // deletes the pump, and the fetcher no longer keeps the manager alive.
    private weak var pumpManager: TandemPumpManager?
    private let fetcher: HistoryLogFetcher

    /// Guards `isRunning`, `rerunRequested` and `sessionCoveredRange`. A tick can be triggered
    /// while the previous one is still walking a slice on the fetcher's queue.
    private let lock = NSLock()
    private var isRunning = false
    /// The pump sends `.bolusChange` at activation and completion, often within one tick.
    private var rerunRequested = false

    /// The span this *session* has read into the store, as distinct from the persisted
    /// watermark.
    ///
    /// The two differ after a relaunch: the watermark says how far the driver has ever read,
    /// while the session store comes back empty. Gap healing and the walk backward are scoped to
    /// this span because both exist to fill the session store — scoping them to the watermark
    /// instead would make a cold start treat its whole history as one enormous hole.
    private var sessionCoveredRange: ClosedRange<UInt32>?

    init(pumpManager: TandemPumpManager, fetcher: HistoryLogFetcher? = nil) {
        self.pumpManager = pumpManager
        self.fetcher = fetcher ?? HistoryLogFetcher(pumpManager: pumpManager)
    }

    /// Run one backfill tick.
    ///
    /// - Parameter completion: Called once the tick finishes, or with nil if it did no work
    ///   (no serial yet, no status, or another reader holds the history stream). Fires on an
    ///   unspecified queue.
    func runTick(now: Date? = nil, completion: ((TickOutcome?) -> Void)? = nil) {
        let now = now ?? pumpManager?.now ?? Date()
        guard pumpManager?.state.featureFlags.historyBackfill == true else {
            // Off means off: no status read, no walk, no bookkeeping. Nothing here is a dry run
            // — a watermark written for entries that were never read would mark them read and
            // suppress them once the flag goes on.
            logger.info("Skipping backfill tick: the History Backfill feature flag is off")
            pumpManager?.historyBackfillMonitor.tickSkipped(.flagOff, at: now)
            completion?(nil)
            return
        }

        guard let pumpManager, let serial = pumpManager.historyLogStoreSerial else {
            // No serial yet means no store key and no bookkeeping identity. Nothing can be
            // filed anywhere findable until a PumpVersionResponse has landed.
            pumpManager?.historyBackfillMonitor.tickSkipped(.noPumpSerial, at: now)
            completion?(nil)
            return
        }

        lock.lock()
        // Checked before the gate, which a running tick holds for most of its length.
        if isRunning {
            rerunRequested = true
            lock.unlock()
            logger.info("Backfill tick already running; another will follow it")
            pumpManager.historyBackfillMonitor.tickSkipped(.queuedBehindRunningTick, at: now)
            completion?(nil)
            return
        }
        guard !pumpManager.historyFetchGate.isBusy else {
            lock.unlock()
            logger.info("Skipping backfill tick: another history reader is active")
            pumpManager.historyBackfillMonitor.tickSkipped(.readerBusy, at: now)
            completion?(nil)
            return
        }
        isRunning = true
        lock.unlock()
        pumpManager.historyBackfillMonitor.tickStarted(at: now)

        let finish: (TickOutcome?) -> Void = { [weak self] outcome in
            guard let self else {
                completion?(outcome)
                return
            }
            if let pumpManager = self.pumpManager {
                pumpManager.historyBackfillMonitor.tickFinished(startedAt: now, finishedAt: pumpManager.now, outcome: outcome)
            }
            if let outcome {
                self.pumpManager?.reportHistoryDoses(after: outcome, now: now)
            }

            self.lock.lock()
            self.isRunning = false
            let rerun = self.rerunRequested
            self.rerunRequested = false
            self.lock.unlock()

            completion?(outcome)
            if rerun {
                self.runTick()
            }
        }

        // Reconcile the persisted bookkeeping against the pump actually connected before
        // anything is read: a replacement pump's sequence numbers mean nothing here.
        let reconciled = (pumpManager.state.historyBackfill ?? HistoryBackfillState(
            firstSeenPumpSerial: serial.rawValue,
            now: now
        )).matching(pumpSerial: serial.rawValue, now: now)

        fetcher.fetchStatus { [weak self] status in
            guard let self else {
                finish(nil)
                return
            }
            guard let status else {
                self.logger.warning("Backfill tick aborted: no history log status")
                finish(nil)
                return
            }
            let reading = HistoryLogStatusReading(status, readAt: pumpManager.now)

            // A pump holding less than has been read from it had its log erased and its counter
            // restarted; drop the stale read position and the session's view of the old
            // numbering.
            let bookkeeping = reconciled.resettingWatermarkIfAbove(lastSequenceNum: status.lastSequenceNum)
            let watermarkWasReset = bookkeeping.watermark != reconciled.watermark
            if watermarkWasReset {
                self.logger.warning(
                    "Pump history log restarted below the watermark " +
                        "(\(String(describing: reconciled.watermark)) > \(status.lastSequenceNum)); " +
                        "re-reading this pump from scratch"
                )
                self.forgetSessionCoverage(pumpSerial: serial)
            }

            let emitFloor = HistoryBackfillPlanner.emitFloor(
                bookkeeping: bookkeeping,
                trackingSince: pumpManager.state.bolusReportLedger.trackingSince,
                now: now
            )

            let plan = HistoryBackfillPlanner.plan(
                firstSequenceNum: status.firstSequenceNum,
                lastSequenceNum: status.lastSequenceNum,
                watermark: bookkeeping.watermark,
                sessionCovered: self.sessionCoverage,
                storeGaps: self.storeGaps(pumpSerial: serial),
                isDeepTargetCovered: self.isDeepTargetCovered(bookkeeping: bookkeeping, now: now)
            )

            guard !plan.isEmpty else {
                self.persist(bookkeeping)
                finish(TickOutcome(
                    bookkeeping: bookkeeping,
                    rangesRead: [],
                    sessionCovered: self.sessionCoverage,
                    isDeepBackfillComplete: plan.isDeepBackfillComplete,
                    emitFloor: emitFloor,
                    pumpStatus: reading,
                    plan: plan,
                    watermarkBefore: reconciled.watermark,
                    watermarkWasReset: watermarkWasReset
                ))
                return
            }

            self.run(
                plan: plan,
                bookkeeping: bookkeeping,
                firstSequenceNum: status.firstSequenceNum,
                now: now
            ) { result in
                self.persist(result.bookkeeping)
                finish(TickOutcome(
                    bookkeeping: result.bookkeeping,
                    rangesRead: result.read,
                    sessionCovered: self.sessionCoverage,
                    isDeepBackfillComplete: self.isDeepTargetCovered(bookkeeping: result.bookkeeping, now: now)
                        || (self.sessionCoverage.map { $0.lowerBound <= status.firstSequenceNum } ?? false),
                    emitFloor: emitFloor,
                    pumpStatus: reading,
                    plan: plan,
                    watermarkBefore: reconciled.watermark,
                    watermarkWasReset: watermarkWasReset,
                    rangesFailed: result.failed,
                    hitDeepSliceCap: result.hitDeepSliceCap
                ))
            }
        }
    }

    // MARK: - Plan execution

    /// Runs a plan's ranges one at a time, newest work first, then steps the deep walk backward
    /// until it reaches the lookback target.
    ///
    /// Sequential rather than concurrent because every fetch shares the one history log stream:
    /// two overlapping walks would each see the other's entries. A failed range is skipped and
    /// re-derived next tick; a failed *deep* slice ends the walk, since every slice after it
    /// steps down from a frontier that did not move.
    private func run(
        plan: HistoryBackfillPlanner.Plan,
        bookkeeping: HistoryBackfillState,
        firstSequenceNum: UInt32,
        now: Date,
        completion: @escaping (RunResult) -> Void
    ) {
        var result = RunResult(bookkeeping: bookkeeping)
        var deepSlicesWalked = 0

        func fetch(_ range: ClosedRange<UInt32>, then: @escaping (Bool) -> Void) {
            let count = Int(range.upperBound - range.lowerBound) + 1
            logger.info("Backfilling history \(range.lowerBound)-\(range.upperBound) (\(count) entries)")

            fetcher.start(numberOfLogs: count, endingAtSequenceNum: range.upperBound) { fetched in
                switch fetched {
                case .success:
                    result.bookkeeping.advanceWatermark(through: range.upperBound)
                    self.noteSessionCoverage(of: range)
                    result.read.append(range)
                    then(true)
                case let .failure(error):
                    self.logger.warning("Backfill range \(range.lowerBound)-\(range.upperBound) failed: \(error)")
                    result.failed.append(range)
                    then(false)
                }
            }
        }

        /// Walks the deep slices, re-deriving each from the frontier the previous one left.
        func stepDeep(_ slice: ClosedRange<UInt32>?) {
            guard let slice else {
                completion(result)
                return
            }
            guard deepSlicesWalked < HistoryBackfillPlanner.maxDeepSlicesPerTick else {
                logger.warning(
                    "Deep backfill hit its per-tick slice cap " +
                        "(\(HistoryBackfillPlanner.maxDeepSlicesPerTick)); resuming next tick"
                )
                result.hitDeepSliceCap = true
                completion(result)
                return
            }
            deepSlicesWalked += 1

            fetch(slice) { succeeded in
                guard succeeded else {
                    completion(result)
                    return
                }
                stepDeep(self.nextDeepSlice(
                    firstSequenceNum: firstSequenceNum,
                    bookkeeping: result.bookkeeping,
                    now: now
                ))
            }
        }

        func next(_ remaining: ArraySlice<ClosedRange<UInt32>>) {
            guard let range = remaining.first else {
                // Re-derived rather than taken from `plan.deep`, which was decided before this
                // tick read anything — on first contact the plan cannot name a slice at all.
                stepDeep(self.nextDeepSlice(
                    firstSequenceNum: firstSequenceNum,
                    bookkeeping: result.bookkeeping,
                    now: now
                ))
                return
            }
            fetch(range) { _ in next(remaining.dropFirst()) }
        }

        next(plan.immediateRanges[...])
    }

    /// The slice to read next, or nil at the target date or the start of the pump's log.
    /// Re-derived per slice so the walk stops on the first entry past the target, not after it.
    private func nextDeepSlice(
        firstSequenceNum: UInt32,
        bookkeeping: HistoryBackfillState,
        now: Date
    ) -> ClosedRange<UInt32>? {
        HistoryBackfillPlanner.deepSlice(
            firstSequenceNum: firstSequenceNum,
            sessionCovered: sessionCoverage,
            isDeepTargetCovered: isDeepTargetCovered(bookkeeping: bookkeeping, now: now)
        )
    }

    // MARK: - Inputs the planner can't compute itself

    private var sessionCoverage: ClosedRange<UInt32>? {
        lock.lock()
        defer { lock.unlock() }
        return sessionCoveredRange
    }

    /// Record that `range` has been read into this session's store.
    private func noteSessionCoverage(of range: ClosedRange<UInt32>) {
        lock.lock()
        if let covered = sessionCoveredRange {
            sessionCoveredRange = min(covered.lowerBound, range.lowerBound) ... max(covered.upperBound, range.upperBound)
        } else {
            sessionCoveredRange = range
        }
        lock.unlock()
    }

    /// Drop this session's view of the store after the pump's numbering restarted: the store is
    /// keyed by (serial, sequence number), so old entries now collide with new ones.
    private func forgetSessionCoverage(pumpSerial: HistoryLogSyncIdentifier.PumpSerial) {
        lock.lock()
        sessionCoveredRange = nil
        lock.unlock()

        do {
            try pumpManager?.historyLogStore.deleteAll(pumpSerial: pumpSerial.rawValue)
        } catch {
            logger.warning("Could not clear the history log store after a log erase: \(error)")
        }
    }

    /// Holes the store reports inside the span this session has read.
    ///
    /// Distinct from the fetcher's own gap-healing pass, which only re-requests what went
    /// missing *within a single fetch*: a range dropped because that fetch was cancelled, or
    /// lost to a disconnect after it ended, is invisible there and shows up here instead. Uses
    /// the store's `missingRanges`, which clamps to the retention watermark so pruned history
    /// isn't mistaken for a hole and chased on every tick.
    private func storeGaps(pumpSerial: HistoryLogSyncIdentifier.PumpSerial) -> [ClosedRange<UInt32>] {
        guard let pumpManager, let covered = sessionCoverage else {
            return []
        }
        do {
            return try pumpManager.historyLogStore.missingRanges(pumpSerial: pumpSerial.rawValue, in: covered)
        } catch {
            logger.warning("Could not read history log store gaps: \(error)")
            return []
        }
    }

    /// Whether the walk backward has already reached far enough to cover insulin still acting.
    ///
    /// Reads the timestamp of the oldest entry in *this session's* span, not the store's oldest
    /// entry overall: the log viewer can put months-old history in the same store, and treating
    /// that as the backfill's reach would declare the recent window covered when it isn't.
    ///
    /// The comparison uses the raw pump clock rather than a reconciled timestamp. A clock change
    /// shifts the boundary by its own delta, which can only stop the walk an interval early or
    /// late, and emitted events are filtered against the reconciled floor separately. Reading a
    /// little too far is the safe direction, so anything unknown here counts as not covered.
    private func isDeepTargetCovered(bookkeeping: HistoryBackfillState, now: Date) -> Bool {
        guard let pumpManager,
              let serial = pumpManager.historyLogStoreSerial,
              let lowest = sessionCoverage?.lowerBound
        else {
            return false
        }

        let boundary: StoredHistoryLog?
        do {
            boundary = try pumpManager.historyLogStore.logs(
                pumpSerial: serial.rawValue,
                in: lowest ... lowest
            ).first
        } catch {
            logger.warning("Could not read the oldest history log of this session's span: \(error)")
            return false
        }
        guard let boundary else {
            return false
        }

        let boundaryDate = Dates.fromJan12008EpochSecondsToDate(TimeInterval(boundary.pumpTimeSec))
        return boundaryDate <= HistoryBackfillPlanner.deepFetchTarget(
            firstSeenFloor: bookkeeping.firstSeenFloor,
            now: now
        )
    }

    private func persist(_ bookkeeping: HistoryBackfillState) {
        guard let pumpManager else {
            return
        }
        pumpManager.state.historyBackfill = bookkeeping
        pumpManager.notifyDelegateStateUpdated()
    }
}
