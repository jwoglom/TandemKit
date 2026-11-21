import Foundation

/// Keeps the session history log store caught up with the pump, in slices small enough that
/// dosing commands never wait long behind it.
///
/// Driven from `syncPumpData`, on LoopKit's own sync cadence. Each tick asks
/// `HistoryBackfillPlanner` what to read, runs those ranges through `HistoryLogFetcher` (which
/// files what streams in into the store and serves what the store already holds), and advances
/// the persisted watermark. Each tick hands its outcome to `TandemPumpManager.reportHistoryDoses`,
/// which decides what reaches the host.
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
        var startedAt: Date = .distantPast
        /// The pump's first and last sequence numbers when the tick began.
        var pumpSequenceRange: ClosedRange<UInt32>?

        /// Whether the store holds the pump's log up to where it stood when the tick began.
        var readsThroughPumpEnd: Bool {
            guard let covered = sessionCovered, let range = pumpSequenceRange else { return false }
            return covered.upperBound >= range.upperBound
        }

        var reachesPumpStart: Bool {
            guard let covered = sessionCovered, let range = pumpSequenceRange else { return false }
            return covered.lowerBound <= range.lowerBound
                || bookkeeping.unreadableThroughSequenceNum.map { Int64(covered.lowerBound) <= Int64($0) + 1 } == true
        }

        /// The session's span above the undatable and pre-service floors: all a pass may date or report.
        var reportableRange: ClosedRange<UInt32>? {
            sessionCovered.flatMap(bookkeeping.readable)
        }
    }

    private let logger = TandemLogger(category: "HistoryBackfill")
    // Weak, not unowned: a tick can still be unwinding on the fetcher's queue after the user
    // deletes the pump, and the fetcher no longer keeps the manager alive.
    private weak var pumpManager: TandemPumpManager?
    private let fetcher: HistoryLogFetcher

    /// Guards `isRunning`, `rerunRequested`, `sessionCoveredRange` and `sessionOldestDate`. A tick can be
    /// triggered while the previous one is still walking a slice on the fetcher's queue.
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

    /// The oldest readable record this session read, dated on the phone's clock when it was read. Kept
    /// rather than looked up: the store may prune that record, and the walk must not take that as uncovered.
    private var sessionOldestDate: Date?

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
            completion?(nil)
            return
        }

        guard let pumpManager, let serial = pumpManager.historyLogStoreSerial else {
            // No serial yet means no store key and no bookkeeping identity. Nothing can be
            // filed anywhere findable until a PumpVersionResponse has landed.
            completion?(nil)
            return
        }

        lock.lock()
        // Checked before the gate, which a running tick holds for most of its length.
        if isRunning {
            rerunRequested = true
            lock.unlock()
            logger.info("Backfill tick already running; another will follow it")
            completion?(nil)
            return
        }
        guard !pumpManager.historyFetchGate.isBusy else {
            lock.unlock()
            logger.info("Skipping backfill tick: another history reader is active")
            completion?(nil)
            return
        }
        isRunning = true
        lock.unlock()

        let finish: (TickOutcome?) -> Void = { [weak self] outcome in
            guard let self else {
                completion?(outcome)
                return
            }
            if let outcome {
                self.pumpManager?.reportHistoryDoses(after: outcome, now: now)
            } else {
                self.pumpManager?.historyTickFailed(startedAt: now)
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
        if let previous = pumpManager.state.historyBackfill, previous.pumpSerial != serial.rawValue {
            forgetSessionSpan()
        }

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

            // A pump holding less than has been read from it had its log erased and its counter
            // restarted; drop the stale read position and the session's view of the old
            // numbering.
            var bookkeeping = reconciled.resettingWatermarkIfAbove(lastSequenceNum: status.lastSequenceNum)
            if bookkeeping.watermark != reconciled.watermark {
                self.logger.warning(
                    "Pump history log restarted below the watermark " +
                        "(\(String(describing: reconciled.watermark)) > \(status.lastSequenceNum)); " +
                        "re-reading this pump from scratch"
                )
                self.forgetSessionCoverage(pumpSerial: serial)
            }
            self.applyHistoryBeforePairing(to: &bookkeeping, status: status, now: now)

            let emitFloor = HistoryBackfillPlanner.emitFloor(
                bookkeeping: bookkeeping,
                trackingSince: pumpManager.state.bolusReportLedger.trackingSince,
                now: now
            )

            let pumpRange = status.firstSequenceNum ... max(status.firstSequenceNum, status.lastSequenceNum)
            // An empty log's range names no entry (faketandem reports 0...0), and a read of it waits out
            // the chunk timeout twice; bookkept as that read of nothing, so coverage and tracking start here.
            if status.numEntries == 0 {
                var read = bookkeeping
                read.advanceWatermark(through: pumpRange.upperBound)
                self.noteSessionCoverage(of: pumpRange)
                self.persist(read)
                finish(TickOutcome(
                    bookkeeping: read,
                    rangesRead: [pumpRange],
                    sessionCovered: self.sessionCoverage,
                    isDeepBackfillComplete: true,
                    emitFloor: emitFloor,
                    startedAt: now,
                    pumpSequenceRange: pumpRange
                ))
                return
            }

            let plan = HistoryBackfillPlanner.plan(
                firstSequenceNum: status.firstSequenceNum,
                lastSequenceNum: status.lastSequenceNum,
                watermark: bookkeeping.watermark,
                sessionCovered: self.sessionCoverage,
                storeGaps: self.storeGaps(pumpSerial: serial),
                isDeepTargetCovered: self.isDeepTargetCovered(bookkeeping: bookkeeping, now: now),
                lowestReadable: self.lowestReadable(bookkeeping: bookkeeping, pumpSerial: serial)
            )

            guard !plan.isEmpty else {
                self.persist(bookkeeping)
                finish(TickOutcome(
                    bookkeeping: bookkeeping,
                    rangesRead: [],
                    sessionCovered: self.sessionCoverage,
                    isDeepBackfillComplete: plan.isDeepBackfillComplete,
                    emitFloor: emitFloor,
                    startedAt: now,
                    pumpSequenceRange: pumpRange
                ))
                return
            }

            self.run(
                plan: plan,
                bookkeeping: bookkeeping,
                firstSequenceNum: status.firstSequenceNum,
                now: now
            ) { updated, rangesRead in
                self.persist(updated)
                finish(TickOutcome(
                    bookkeeping: updated,
                    rangesRead: rangesRead,
                    sessionCovered: self.sessionCoverage,
                    isDeepBackfillComplete: self.isDeepTargetCovered(bookkeeping: updated, now: now)
                        || (self.sessionCoverage.map {
                            $0.lowerBound <= max(status.firstSequenceNum, self.lowestReadable(bookkeeping: updated, pumpSerial: serial))
                        } ?? false),
                    emitFloor: emitFloor,
                    startedAt: now,
                    pumpSequenceRange: pumpRange
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
        completion: @escaping (HistoryBackfillState, [ClosedRange<UInt32>]) -> Void
    ) {
        var bookkeeping = bookkeeping
        var read: [ClosedRange<UInt32>] = []
        var deepSlicesWalked = 0

        func fetch(_ range: ClosedRange<UInt32>, then: @escaping (Bool) -> Void) {
            let count = Int(range.upperBound - range.lowerBound) + 1
            logger.info("Backfilling history \(range.lowerBound)-\(range.upperBound) (\(count) entries)")

            fetcher.start(numberOfLogs: count, endingAtSequenceNum: range.upperBound) { result in
                switch result {
                case .success:
                    bookkeeping.advanceWatermark(through: range.upperBound)
                    self.noteSessionCoverage(of: range)
                    self.noteUndatableHistory(in: range, bookkeeping: &bookkeeping)
                    self.dateSessionOldest(bookkeeping: bookkeeping)
                    read.append(range)
                    then(true)
                case let .failure(error):
                    self.logger.warning("Backfill range \(range.lowerBound)-\(range.upperBound) failed: \(error)")
                    then(false)
                }
            }
        }

        /// Walks the deep slices, re-deriving each from the frontier the previous one left.
        func stepDeep(_ slice: ClosedRange<UInt32>?) {
            guard let slice else {
                completion(bookkeeping, read)
                return
            }
            guard deepSlicesWalked < HistoryBackfillPlanner.maxDeepSlicesPerTick else {
                logger.warning(
                    "Deep backfill hit its per-tick slice cap " +
                        "(\(HistoryBackfillPlanner.maxDeepSlicesPerTick)); resuming next tick"
                )
                completion(bookkeeping, read)
                return
            }
            deepSlicesWalked += 1

            fetch(slice) { succeeded in
                guard succeeded else {
                    completion(bookkeeping, read)
                    return
                }
                stepDeep(self.nextDeepSlice(
                    firstSequenceNum: firstSequenceNum,
                    bookkeeping: bookkeeping,
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
                    bookkeeping: bookkeeping,
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
            isDeepTargetCovered: isDeepTargetCovered(bookkeeping: bookkeeping, now: now),
            lowestReadable: pumpManager?.historyLogStoreSerial.map { lowestReadable(bookkeeping: bookkeeping, pumpSerial: $0) } ?? 0
        )
    }

    // MARK: - Inputs the planner can't compute itself

    var isTickRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunning
    }

    /// The oldest and newest records this session has read, on the phone's clock, including those of a
    /// slice still streaming in. A slice is noted as covered only once it ends, several seconds after
    /// its first entries arrive, and one slice spans most of a setup load's window.
    func sessionPhoneTimeSpan() -> ClosedRange<Date>? {
        guard let pumpManager, let serial = pumpManager.historyLogStoreSerial else {
            return nil
        }
        let bookkeeping = pumpManager.state.historyBackfill
        var ends: [UInt32] = []
        if let covered = sessionCoverage {
            ends.append(covered.upperBound)
        }
        if let streaming = fetcher.progressInFlight {
            ends += [streaming.earliestFetchedSequenceNum, streaming.latestFetchedSequenceNum].compactMap { $0 }
        }
        var dates = ends.compactMap { datedRecord(at: $0, pumpSerial: serial, bookkeeping: bookkeeping) }
        if let oldest = sessionOldestDateValue {
            dates.append(oldest)
        }
        guard let oldest = dates.min(), let newest = dates.max() else {
            return nil
        }
        return oldest ... newest
    }

    var sessionCoverage: ClosedRange<UInt32>? {
        lock.lock()
        defer { lock.unlock() }
        return sessionCoveredRange
    }

    private var sessionOldestDateValue: Date? {
        lock.lock()
        defer { lock.unlock() }
        return sessionOldestDate
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
        forgetSessionSpan()

        do {
            try pumpManager?.historyLogStore.deleteAll(pumpSerial: pumpSerial.rawValue)
        } catch {
            logger.warning("Could not clear the history log store after a log erase: \(error)")
        }
    }

    private func forgetSessionSpan() {
        lock.lock()
        sessionCoveredRange = nil
        sessionOldestDate = nil
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

    /// Whether the walk backward has already reached far enough to cover insulin still acting: whether
    /// the oldest record this session read is dated at or before the target, both on the phone's clock.
    private func isDeepTargetCovered(bookkeeping: HistoryBackfillState, now: Date) -> Bool {
        guard let oldest = sessionOldestDateValue else {
            return false
        }
        return oldest <= HistoryBackfillPlanner.deepFetchTarget(firstSeenFloor: bookkeeping.firstSeenFloor, now: now)
    }

    /// Nothing at or below the undatable or pre-service floor is read, nor below what the store has pruned: read again,
    /// it would be pruned at the next pass and the walk would go a slice deeper each time.
    private func lowestReadable(bookkeeping: HistoryBackfillState, pumpSerial serial: HistoryLogSyncIdentifier.PumpSerial) -> UInt32 {
        let prunedBelow: UInt32?
        do {
            prunedBelow = try pumpManager?.historyLogStore.prunedBelowSequenceNum(pumpSerial: serial.rawValue)
        } catch {
            logger.warning("Could not read the history log store's retention watermark: \(error)")
            prunedBelow = nil
        }
        let readable = bookkeeping.unreadableThroughSequenceNum.map { $0 == .max ? $0 : $0 + 1 } ?? 0
        return max(readable, prunedBelow ?? 0)
    }

    /// Takes the pre-service floor at the first status read after setup pairs, or the one setup's load
    /// leaves. Re-applied every tick: a tick that began before the load saves the floor it started with.
    private func applyHistoryBeforePairing(to bookkeeping: inout HistoryBackfillState, status: HistoryLogStatusResponse, now: Date) {
        guard let pumpManager else {
            return
        }
        switch pumpManager.state.takeHistoryBeforePairing() {
        case .held:
            guard status.numEntries > 0 else {
                return
            }
            logger.info("Pump history through #\(status.lastSequenceNum) is from before setup paired the pump; none of it is read unless setup loads it")
            bookkeeping.preServiceThroughSequenceNum = status.lastSequenceNum
            bookkeeping.serviceStartDate = now
        case let .loaded(through, since):
            bookkeeping.preServiceThroughSequenceNum = through
            bookkeeping.serviceStartDate = since
        case .read, .floored:
            break
        }
    }

    /// Raises the saved floor to the newest ShelfMode or ArmInit record read. A stamp running back is left
    /// to each pass, which reads every record; this reads the clock records alone.
    private func noteUndatableHistory(in range: ClosedRange<UInt32>, bookkeeping: inout HistoryBackfillState) {
        guard let pumpManager, let serial = pumpManager.historyLogStoreSerial else {
            return
        }
        let upper = max(range.upperBound, sessionCoverage?.upperBound ?? range.upperBound)
        let clock: [HistoryLog]
        do {
            clock = try pumpManager.historyLogStore
                .logs(pumpSerial: serial.rawValue, ofTypes: HistoryTimestampReconciler.clockHistoryTypes, in: range.lowerBound ... upper)
                .map { $0.parsed() }
        } catch {
            logger.warning("Could not read the clock records in history \(range.lowerBound)-\(upper): \(error)")
            return
        }
        guard let undatable = pumpManager.historyRecordDates(clock).undatableThroughSequenceNum,
              bookkeeping.undatableThroughSequenceNum.map({ undatable > $0 }) ?? true
        else {
            return
        }
        bookkeeping.raiseUndatableThrough(to: undatable)
    }

    /// Dates the oldest readable record this session holds, after every read: a slice deeper moves it,
    /// and a clock change read since moves its date.
    private func dateSessionOldest(bookkeeping: HistoryBackfillState) {
        guard let pumpManager, let serial = pumpManager.historyLogStoreSerial,
              let readable = sessionCoverage.flatMap(bookkeeping.readable)
        else {
            return
        }
        let lowest: UInt32?
        do {
            lowest = try pumpManager.historyLogStore.sequenceNumbers(pumpSerial: serial.rawValue, in: readable).first
        } catch {
            logger.warning("Could not read the oldest history log of this session's span: \(error)")
            return
        }
        guard let lowest, let date = datedRecord(at: lowest, pumpSerial: serial, bookkeeping: bookkeeping) else {
            return
        }
        lock.lock()
        sessionOldestDate = date
        lock.unlock()
    }

    /// A stored record dated on the phone's clock, past every clock change this session read after it.
    private func datedRecord(
        at sequenceNum: UInt32,
        pumpSerial serial: HistoryLogSyncIdentifier.PumpSerial,
        bookkeeping: HistoryBackfillState?
    ) -> Date? {
        guard let pumpManager, bookkeeping?.undatableThroughSequenceNum.map({ sequenceNum > $0 }) ?? true else {
            return nil
        }
        let upper = max(sequenceNum, sessionCoverage?.upperBound ?? sequenceNum)
        do {
            let store = pumpManager.historyLogStore
            guard let record = try store.logs(pumpSerial: serial.rawValue, in: sequenceNum ... sequenceNum).first else {
                return nil
            }
            let clock = try store.logs(pumpSerial: serial.rawValue, ofTypes: HistoryTimestampReconciler.clockHistoryTypes, in: sequenceNum ... upper)
            let dates = pumpManager.historyRecordDates(clock.map { $0.parsed() })
            return dates.phoneDate(pumpTimeSec: record.pumpTimeSec, sequenceNum: record.sequenceNum)
        } catch {
            logger.warning("Could not date history log \(sequenceNum): \(error)")
            return nil
        }
    }

    private func persist(_ bookkeeping: HistoryBackfillState) {
        guard let pumpManager else {
            return
        }
        pumpManager.state.historyBackfill = bookkeeping
        pumpManager.notifyDelegateStateUpdated()
    }
}
