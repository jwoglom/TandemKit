import Foundation

/// Keeps the session history log store caught up with the pump, in slices small enough that
/// dosing commands never wait long behind it.
///
/// Driven from `syncPumpData`, on LoopKit's own sync cadence. Each tick asks
/// `HistoryBackfillPlanner` what to read, runs those ranges through `HistoryLogFetcher` (which
/// files what streams in into the store and serves what the store already holds), and advances
/// the persisted watermark. Nothing is mapped to doses or emitted here — that is the emission
/// layer's job; this type's outputs are a fuller store and up-to-date bookkeeping.
final class HistoryBackfillCoordinator {
    /// What one tick did. Returned to the caller and to tests; the emission layer will read
    /// `sessionCovered` and `isDeepBackfillComplete` to decide how much of its window it can
    /// account for.
    struct TickOutcome: Equatable {
        /// Bookkeeping as persisted at the end of the tick.
        var bookkeeping: HistoryBackfillState
        /// Ranges the tick actually read, in the order they were read.
        var rangesRead: [ClosedRange<UInt32>]
        /// The span this session has read into the store, after the tick.
        var sessionCovered: ClosedRange<UInt32>?
        /// Whether the walk backward has nothing left to reach.
        var isDeepBackfillComplete: Bool
    }

    private let logger = TandemLogger(category: "HistoryBackfill")
    private unowned let pumpManager: TandemPumpManager
    private let fetcher: HistoryLogFetcher

    /// Guards `isRunning` and `sessionCoveredRange`. A tick can be triggered while the previous
    /// one is still walking a slice on the fetcher's queue.
    private let lock = NSLock()
    private var isRunning = false

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
    func runTick(now: Date = Date(), completion: ((TickOutcome?) -> Void)? = nil) {
        guard let serial = pumpManager.historyLogStoreSerial else {
            // No serial yet means no store key and no bookkeeping identity. Nothing can be
            // filed anywhere findable until a PumpVersionResponse has landed.
            completion?(nil)
            return
        }

        guard !pumpManager.historyFetchGate.isBusy else {
            logger.info("Skipping backfill tick: another history reader is active")
            completion?(nil)
            return
        }

        lock.lock()
        if isRunning {
            lock.unlock()
            logger.info("Skipping backfill tick: previous tick still running")
            completion?(nil)
            return
        }
        isRunning = true
        lock.unlock()

        let finish: (TickOutcome?) -> Void = { [weak self] outcome in
            self?.lock.lock()
            self?.isRunning = false
            self?.lock.unlock()
            completion?(outcome)
        }

        // Reconcile the persisted bookkeeping against the pump actually connected before
        // anything is read: a replacement pump's sequence numbers mean nothing here.
        var bookkeeping = (pumpManager.state.historyBackfill ?? HistoryBackfillState(
            firstSeenPumpSerial: serial.rawValue,
            now: now
        )).matching(pumpSerial: serial.rawValue, now: now)
        bookkeeping.emitFloor = HistoryBackfillPlanner.emitFloor(
            hostFloor: pumpManager.hostEventFloor,
            bookkeeping: bookkeeping
        )

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

            let plan = HistoryBackfillPlanner.plan(
                firstSequenceNum: status.firstSequenceNum,
                lastSequenceNum: status.lastSequenceNum,
                watermark: bookkeeping.watermark,
                sessionCovered: self.sessionCoverage,
                storeGaps: self.storeGaps(pumpSerial: serial),
                isDeepTargetCovered: self.isDeepTargetCovered(emitFloor: bookkeeping.emitFloor, now: now)
            )

            guard !plan.isEmpty else {
                self.persist(bookkeeping)
                finish(TickOutcome(
                    bookkeeping: bookkeeping,
                    rangesRead: [],
                    sessionCovered: self.sessionCoverage,
                    isDeepBackfillComplete: plan.isDeepBackfillComplete
                ))
                return
            }

            self.run(plan: plan, bookkeeping: bookkeeping) { updated, rangesRead in
                self.persist(updated)
                finish(TickOutcome(
                    bookkeeping: updated,
                    rangesRead: rangesRead,
                    sessionCovered: self.sessionCoverage,
                    isDeepBackfillComplete: plan.isDeepBackfillComplete
                ))
            }
        }
    }

    // MARK: - Plan execution

    /// Runs a plan's ranges one at a time, newest work first, advancing the watermark as each
    /// range completes.
    ///
    /// Sequential rather than concurrent because every fetch shares the one history log stream:
    /// two overlapping walks would each see the other's entries and neither could tell when its
    /// own chunk was complete. A range that fails is skipped rather than retried — the next tick
    /// re-derives it, as new work or as a gap.
    private func run(
        plan: HistoryBackfillPlanner.Plan,
        bookkeeping: HistoryBackfillState,
        completion: @escaping (HistoryBackfillState, [ClosedRange<UInt32>]) -> Void
    ) {
        var ranges: [ClosedRange<UInt32>] = []
        if let incremental = plan.incremental {
            ranges.append(incremental)
        }
        ranges.append(contentsOf: plan.gaps.sorted { $0.lowerBound > $1.lowerBound })
        if let deep = plan.deep {
            ranges.append(deep)
        }

        var bookkeeping = bookkeeping
        var read: [ClosedRange<UInt32>] = []

        func next(_ remaining: ArraySlice<ClosedRange<UInt32>>) {
            guard let range = remaining.first else {
                completion(bookkeeping, read)
                return
            }

            let count = Int(range.upperBound - range.lowerBound) + 1
            logger.info("Backfilling history \(range.lowerBound)-\(range.upperBound) (\(count) entries)")

            fetcher.start(numberOfLogs: count, endingAtSequenceNum: range.upperBound) { result in
                switch result {
                case .success:
                    bookkeeping.advanceWatermark(through: range.upperBound)
                    self.noteSessionCoverage(of: range)
                    read.append(range)
                case let .failure(error):
                    self.logger.warning("Backfill range \(range.lowerBound)-\(range.upperBound) failed: \(error)")
                }
                next(remaining.dropFirst())
            }
        }

        next(ranges[...])
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

    /// Holes the store reports inside the span this session has read.
    ///
    /// Distinct from the fetcher's own gap-healing pass, which only re-requests what went
    /// missing *within a single fetch*: a range dropped because that fetch was cancelled, or
    /// lost to a disconnect after it ended, is invisible there and shows up here instead. Uses
    /// the store's `missingRanges`, which clamps to the retention watermark so pruned history
    /// isn't mistaken for a hole and chased on every tick.
    private func storeGaps(pumpSerial: HistoryLogSyncIdentifier.PumpSerial) -> [ClosedRange<UInt32>] {
        guard let covered = sessionCoverage else {
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
    private func isDeepTargetCovered(emitFloor: Date?, now: Date) -> Bool {
        guard let serial = pumpManager.historyLogStoreSerial,
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
        return boundaryDate <= HistoryBackfillPlanner.deepFetchTarget(emitFloor: emitFloor, now: now)
    }

    private func persist(_ bookkeeping: HistoryBackfillState) {
        pumpManager.state.historyBackfill = bookkeeping
        pumpManager.notifyDelegateStateUpdated()
    }
}
