import Combine
import Foundation
@testable import TandemKit
import XCTest

/// Drives `HistoryBackfillCoordinator` against the stub pump, checking that a tick reads the
/// right ranges, advances the persisted bookkeeping, and stays out of the way of other readers.
///
/// The stub reproduces the pump's split reply to a `HistoryLogRequest` — an acknowledgement from
/// the write, the entries as unsolicited notifications on `historyLogStream` — the same way
/// `TandemPumpManagerHistoryIntegrationTests` does, so the fetch underneath each tick is real.
@available(macOS 13.0, iOS 14.0, *) final class HistoryBackfillCoordinatorTests: XCTestCase {
    private static let pumpSerial: UInt32 = 123_456

    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var coordinator: HistoryBackfillCoordinator!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: Self.backfillEnabledState(), bluetooth: bluetooth)
        coordinator = HistoryBackfillCoordinator(pumpManager: manager)
    }

    /// Fetching is gated behind the `historyBackfill` flag. It is on by default, but every test
    /// below drives the read path, so they pin it on rather than depend on the default.
    private static func backfillEnabledState() -> TandemPumpManagerState {
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.historyBackfill] = true
        return state
    }

    override func tearDown() {
        coordinator = nil
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private lazy var basePumpTimeSec = UInt32(Dates.fromInstantToJan12008EpochSeconds(Date()))

    /// An entry whose pump clock runs one minute per sequence number, so a window of sequence
    /// numbers maps to a predictable stretch of time.
    private func log(sequenceNum: UInt32, ageSeconds: UInt32 = 0) -> BolusActivatedHistoryLog {
        BolusActivatedHistoryLog(
            pumpTimeSec: basePumpTimeSec - ageSeconds,
            sequenceNum: sequenceNum,
            bolusId: Int(sequenceNum),
            selectedIob: 0,
            iob: 0,
            bolusSize: 1.0
        )
    }

    private func setPumpSerial(_ serial: UInt32 = pumpSerial) {
        manager.state.pumpState.pumpSerial = serial
    }

    private func stubStatus(first: UInt32, last: UInt32) {
        bluetooth.stub(HistoryLogStatusRequest.self, with: HistoryLogStatusResponse(
            numEntries: last - first + 1,
            firstSequenceNum: first,
            lastSequenceNum: last
        ))
    }

    /// Streams back whatever each `HistoryLogRequest` asks for. `secondsPerSequence` ages entries
    /// as their sequence numbers fall, so the deep backfill's date boundary can be exercised.
    private func stubHistoryStream(secondsPerSequence: UInt32 = 0, newestSequenceNum: UInt32 = 0, streamId: Int = 7) {
        bluetooth.stub(HistoryLogRequest.self, with: HistoryLogResponse(status: 0, streamId: streamId))

        bluetooth.onWrite = { [weak self] message in
            guard let self, let request = message as? HistoryLogRequest else { return }

            let top = Int(request.startLog)
            let bottom = max(0, top - max(request.numberOfLogs, 1) + 1)
            let logs = stride(from: top, through: bottom, by: -1).map { sequence -> BolusActivatedHistoryLog in
                let age = secondsPerSequence * (newestSequenceNum > UInt32(sequence) ? newestSequenceNum - UInt32(sequence) : 0)
                return self.log(sequenceNum: UInt32(sequence), ageSeconds: age)
            }
            guard !logs.isEmpty else { return }

            self.manager.historyLogStream.send(HistoryLogStreamResponse(
                numberOfHistoryLogs: logs.count,
                streamId: streamId,
                historyLogStreamBytes: logs.map(\.cargo)
            ))
        }
    }

    /// Ages entries so that `sequences` sequence numbers span exactly one `deepFetchLookback`,
    /// putting the walk's target a predictable number of slices down.
    private func secondsPerSequence(spanning sequences: UInt32) -> UInt32 {
        UInt32(HistoryBackfillPlanner.deepFetchLookback) / sequences
    }

    @discardableResult
    private func runTick(now: Date = Date()) -> HistoryBackfillCoordinator.TickOutcome? {
        var result: HistoryBackfillCoordinator.TickOutcome?
        let expectation = expectation(description: "backfill tick completes")
        coordinator.runTick(now: now) {
            result = $0
            expectation.fulfill()
        }
        // Each range walked costs the fetcher a fixed post-request delay plus polling; a range
        // that never completes burns its chunk timeout. Allow well beyond the happy path.
        wait(for: [expectation], timeout: 90.0)
        return result
    }

    private func requestedStartLogs() -> [UInt32] {
        bluetooth.sent(HistoryLogRequest.self).map(\.startLog)
    }

    // MARK: - Preconditions

    /// The store and the bookkeeping are both keyed by serial, so neither can be written before a
    /// PumpVersionResponse has supplied one.
    func testTickDoesNothingBeforeTheSerialIsKnown() {
        stubStatus(first: 1, last: 10)
        stubHistoryStream()

        XCTAssertNil(runTick())
        XCTAssertNil(manager.state.historyBackfill)
        XCTAssertTrue(bluetooth.sent(HistoryLogRequest.self).isEmpty)
    }

    func testTickDoesNothingWhenTheStatusCannotBeRead() {
        setPumpSerial()
        stubHistoryStream()

        XCTAssertNil(runTick())
        XCTAssertNil(manager.state.historyBackfill)
    }

    // MARK: - First contact

    func testFirstTickReadsTheNewestSliceAndRecordsIt() throws {
        setPumpSerial()
        stubStatus(first: 1, last: 10)
        stubHistoryStream()

        let outcome = try XCTUnwrap(runTick())

        XCTAssertEqual(outcome.bookkeeping.pumpSerial, Self.pumpSerial)
        XCTAssertEqual(outcome.bookkeeping.watermark, 10)
        XCTAssertEqual(outcome.sessionCovered, 1 ... 10)
        XCTAssertEqual(manager.state.historyBackfill, outcome.bookkeeping, "Bookkeeping must be persisted")
        XCTAssertEqual(try manager.historyLogStore.count(pumpSerial: Self.pumpSerial), 10)
    }

    // MARK: - Incremental

    func testSecondTickReadsOnlyWhatIsNew() throws {
        setPumpSerial()
        stubStatus(first: 1, last: 10)
        stubHistoryStream()
        _ = runTick()

        bluetooth.resetRecordedTraffic()
        stubStatus(first: 1, last: 13)
        stubHistoryStream()

        let outcome = try XCTUnwrap(runTick())

        XCTAssertEqual(outcome.bookkeeping.watermark, 13)
        XCTAssertEqual(outcome.rangesRead, [11 ... 13])
        XCTAssertEqual(requestedStartLogs(), [13], "Only the entries written since the watermark")
        XCTAssertEqual(bluetooth.sent(HistoryLogRequest.self).first?.numberOfLogs, 3)
    }

    /// A cold start resumes from the persisted watermark rather than re-walking the pump into an
    /// empty session store — the whole reason the bookkeeping is persisted at all.
    func testRelaunchResumesFromThePersistedWatermark() throws {
        setPumpSerial()
        var state = Self.backfillEnabledState()
        state.pumpState.pumpSerial = Self.pumpSerial
        state.historyBackfill = HistoryBackfillState(
            pumpSerial: Self.pumpSerial,
            watermark: 900,
            firstSeenFloor: Date().addingTimeInterval(-.hours(1))
        )
        // A fresh manager, as after a relaunch: persisted state, empty in-memory store.
        manager = TandemPumpManager(state: state, bluetooth: bluetooth)
        coordinator = HistoryBackfillCoordinator(pumpManager: manager)

        stubStatus(first: 1, last: 910)
        stubHistoryStream(secondsPerSequence: secondsPerSequence(spanning: 600), newestSequenceNum: 910)

        let outcome = try XCTUnwrap(runTick())

        XCTAssertEqual(
            requestedStartLogs().first,
            910,
            "The read of new entries starts at the watermark, not at the empty session store's floor"
        )
        XCTAssertEqual(
            bluetooth.sent(HistoryLogRequest.self).first?.numberOfLogs,
            10,
            "Ten entries written since the watermark, not the 1-900 span the session store lacks"
        )
        XCTAssertEqual(outcome.bookkeeping.watermark, 910)

        // The session store came back empty, so the walk refills the lookback window behind the
        // watermark — that is what IOB is computed from — and stops there rather than at the
        // start of the pump's log.
        let covered = try XCTUnwrap(outcome.sessionCovered)
        XCTAssertEqual(covered.upperBound, 910)
        XCTAssertGreaterThan(covered.lowerBound, 1, "The walk stops at the target, not at sequence 1")
        XCTAssertTrue(outcome.isDeepBackfillComplete)
    }

    func testTickWithNothingToDoLeavesTheWatermarkAlone() throws {
        setPumpSerial()
        stubStatus(first: 1, last: 10)
        stubHistoryStream()
        let first = try XCTUnwrap(runTick())

        bluetooth.resetRecordedTraffic()
        stubStatus(first: 1, last: 10)
        stubHistoryStream()
        let second = try XCTUnwrap(runTick())

        XCTAssertEqual(second.bookkeeping, first.bookkeeping)
        XCTAssertTrue(second.rangesRead.isEmpty)
        XCTAssertTrue(bluetooth.sent(HistoryLogRequest.self).isEmpty)
    }

    // MARK: - Gap healing across ticks

    /// A range lost after its fetch ended is invisible to the fetcher's own intra-fetch healing.
    /// The next tick sees it as a hole in the store and re-requests it.
    func testGapLeftBehindByAnEarlierFetchIsHealedOnTheNextTick() throws {
        setPumpSerial()
        stubStatus(first: 1, last: 10)
        stubHistoryStream()
        _ = runTick()

        try manager.historyLogStore.deleteAll(pumpSerial: Self.pumpSerial)
        try manager.historyLogStore.insert(
            [1, 2, 3, 7, 8, 9, 10].map { log(sequenceNum: $0) },
            pumpSerial: Self.pumpSerial
        )

        bluetooth.resetRecordedTraffic()
        stubStatus(first: 1, last: 10)
        stubHistoryStream()
        _ = runTick()

        XCTAssertEqual(requestedStartLogs(), [6], "The 4...6 hole, requested from its top")
        XCTAssertEqual(try manager.historyLogStore.count(pumpSerial: Self.pumpSerial), 10)
    }

    // MARK: - Deep backfill

    /// The walk is sliced, but not paced one slice per sync: everything short of the target is
    /// insulin that may still be acting, so the first tick on a new pump reads all of it. A
    /// slice per five-minute sync would leave IOB short for hours after the pump was added.
    func testDeepBackfillWalksToTheTargetWithinTheFirstTick() throws {
        setPumpSerial()
        let now = Date()
        let slice = HistoryBackfillPlanner.maxDeepSliceSize
        // One lookback spans 1000 sequence numbers, so the target sits four slices down.
        stubStatus(first: 1, last: 5000)
        stubHistoryStream(secondsPerSequence: secondsPerSequence(spanning: 1000), newestSequenceNum: 5000)

        let outcome = try XCTUnwrap(runTick(now: now))

        XCTAssertTrue(outcome.isDeepBackfillComplete)
        XCTAssertGreaterThan(
            requestedStartLogs().count, 1,
            "The walk continues past the first slice within the same tick"
        )
        let covered = try XCTUnwrap(outcome.sessionCovered)
        XCTAssertEqual(covered.upperBound, 5000)
        XCTAssertLessThanOrEqual(
            covered.lowerBound, 5000 - slice,
            "The window reaches back past the newest slice"
        )

        // Each slice is still its own set of command-queue jobs rather than one long block, so
        // dosing interleaves with the walk.
        XCTAssertTrue(
            bluetooth.sent(HistoryLogRequest.self).allSatisfy { $0.numberOfLogs <= Int(slice) },
            "No request may exceed one chunk"
        )
    }

    /// Once this session's span reaches back past the target date the walk stops, however much
    /// older history the pump still holds.
    func testDeepBackfillStopsOnceTheTargetDateIsCovered() throws {
        setPumpSerial()
        let now = Date()
        // Age entries steeply enough that the first slice alone reaches past the boundary.
        let steep = secondsPerSequence(spanning: 100)
        stubStatus(first: 1, last: 5000)
        stubHistoryStream(secondsPerSequence: steep, newestSequenceNum: 5000)

        let first = try XCTUnwrap(runTick(now: now))
        XCTAssertTrue(first.isDeepBackfillComplete)
        XCTAssertEqual(requestedStartLogs(), [5000], "One slice already covers the target")

        bluetooth.resetRecordedTraffic()
        stubStatus(first: 1, last: 5000)
        stubHistoryStream(secondsPerSequence: steep, newestSequenceNum: 5000)
        let second = try XCTUnwrap(runTick(now: now))

        XCTAssertTrue(second.isDeepBackfillComplete)
        XCTAssertTrue(requestedStartLogs().isEmpty, "Nothing left to read once the target is covered")
    }

    /// The per-tick slice cap is a backstop for a walk that is not converging — a pump clock far
    /// in the future, say — so one tick can't read the pump's whole log. The walk resumes on the
    /// next tick rather than being abandoned.
    func testDeepBackfillStopsAtThePerTickSliceCapAndResumes() throws {
        setPumpSerial()
        let slice = HistoryBackfillPlanner.maxDeepSliceSize
        let cap = HistoryBackfillPlanner.maxDeepSlicesPerTick
        // Every entry stamped ≈now, so the walk never reaches the target by date.
        stubStatus(first: 1, last: slice * UInt32(cap + 2))
        stubHistoryStream()

        let first = try XCTUnwrap(runTick())

        XCTAssertEqual(
            requestedStartLogs().count, cap + 1,
            "One incremental read plus the capped number of deep slices"
        )
        XCTAssertFalse(first.isDeepBackfillComplete)
        let covered = try XCTUnwrap(first.sessionCovered)
        XCTAssertGreaterThan(covered.lowerBound, 1, "The walk stopped short of the pump's oldest entry")

        bluetooth.resetRecordedTraffic()
        stubStatus(first: 1, last: slice * UInt32(cap + 2))
        stubHistoryStream()
        let second = try XCTUnwrap(runTick())

        XCTAssertEqual(
            requestedStartLogs().first, covered.lowerBound - 1,
            "The next tick resumes below the frontier the capped tick left"
        )
        XCTAssertTrue(second.isDeepBackfillComplete, "The remaining slices reach the start of the log")
    }

    // MARK: - Dating the walk's stop

    /// Serves exactly `logs`, newest first per request, the way the pump streams them.
    private func stubHistory(serving logs: [HistoryLog], streamId: Int = 7) {
        let bySequence = Dictionary(uniqueKeysWithValues: logs.map { ($0.sequenceNum, $0) })
        let sequences = logs.map(\.sequenceNum)
        stubStatus(first: sequences.min()!, last: sequences.max()!)
        bluetooth.stub(HistoryLogRequest.self, with: HistoryLogResponse(status: 0, streamId: streamId))
        bluetooth.onWrite = { [weak self] message in
            guard let self, let request = message as? HistoryLogRequest else { return }
            let top = request.startLog
            let count = UInt32(max(request.numberOfLogs, 1))
            let bottom = top >= count ? top - count + 1 : 0
            let streamed = stride(from: top, through: bottom, by: -1).compactMap { bySequence[$0] }
            guard !streamed.isEmpty else { return }
            self.manager.historyLogStream.send(HistoryLogStreamResponse(
                numberOfHistoryLogs: streamed.count,
                streamId: streamId,
                historyLogStreamBytes: streamed.map(\.cargo)
            ))
        }
    }

    private func requestedRanges() -> [ClosedRange<UInt32>] {
        bluetooth.sent(HistoryLogRequest.self).map { request in
            let count = UInt32(max(request.numberOfLogs, 1))
            return (request.startLog >= count ? request.startLog - count + 1 : 0) ... request.startLog
        }
    }

    private static let restartedClockDays: UInt32 = 400

    /// `count` records a minute apart up to now, every one but the newest ten stamped on a clock
    /// `restartedClockDays` behind, as a pump's after a reset, until a `DateChange` at `count - 10` set it.
    private func historyAcrossAClockWrite(count: UInt32) -> [HistoryLog] {
        let behind = Self.restartedClockDays * 86400
        let changeAt = count - 10
        return (1 ... count).map { sequence -> HistoryLog in
            let stamp = basePumpTimeSec - (count - sequence) * 60
            if sequence == changeAt {
                return DateChangeHistoryLog(
                    pumpTimeSec: stamp,
                    sequenceNum: sequence,
                    datePrior: 1000,
                    dateAfter: 1000 + Self.restartedClockDays,
                    rawRTCTime: 0
                )
            }
            return log(sequenceNum: sequence, ageSeconds: (count - sequence) * 60 + (sequence < changeAt ? behind : 0))
        }
    }

    /// Stamped on the restarted clock, the oldest record of the first slice reads 400 days old. Compared
    /// raw against the target, the walk stopped there, four hours short of the insulin still acting.
    func testTheWalkStopsByTheDateTheClockChangeGivesItsOldestRecord() throws {
        setPumpSerial()
        stubHistory(serving: historyAcrossAClockWrite(count: 600))

        let outcome = try XCTUnwrap(runTick())

        XCTAssertTrue(outcome.isDeepBackfillComplete)
        // The lookback reaches record 180, inside the second slice.
        XCTAssertEqual(requestedRanges(), [346 ... 600, 91 ... 345])
        XCTAssertEqual(outcome.sessionCovered, 91 ... 600)
    }

    /// In a field log the hourly prune, by stamp, took the walk's oldest record every hour, and the walk
    /// read a slice deeper each time, past a ShelfMode record into boluses from the pump's previous use.
    func testAnHourlyPruneLeavesRecordsStampedYearsAgoAndTheWalkWhereItStopped() throws {
        setPumpSerial()
        let history = historyAcrossAClockWrite(count: 600)
        stubHistory(serving: history)
        let start = Date()
        _ = try XCTUnwrap(runTick(now: start))
        let stored = try manager.historyLogStore.count(pumpSerial: Self.pumpSerial)

        for hour in 1 ... 3 {
            let later = start.addingTimeInterval(.hours(Double(hour)) + .minutes(1))
            manager.pruneHistoryLogStoreIfNeeded(now: later)
            XCTAssertEqual(try manager.historyLogStore.count(pumpSerial: Self.pumpSerial), stored, "hour \(hour)")

            bluetooth.resetRecordedTraffic()
            stubHistory(serving: history)
            _ = try XCTUnwrap(runTick(now: later))
            XCTAssertTrue(requestedRanges().isEmpty, "hour \(hour) read \(requestedRanges())")
        }
    }

    func testAPruneBelowTheWalksOldestRecordDoesNotReopenTheWalk() throws {
        setPumpSerial()
        let history = historyAcrossAClockWrite(count: 600)
        stubHistory(serving: history)
        let first = try XCTUnwrap(runTick())
        let lowest = try XCTUnwrap(first.sessionCovered?.lowerBound)

        try manager.historyLogStore.prune(pumpSerial: Self.pumpSerial, belowSequenceNum: lowest + 10)
        bluetooth.resetRecordedTraffic()
        stubHistory(serving: history)
        let second = try XCTUnwrap(runTick())

        XCTAssertTrue(requestedRanges().isEmpty, "read \(requestedRanges())")
        XCTAssertTrue(second.isDeepBackfillComplete)
    }

    // MARK: - Shelf mode

    private func shelfMode(sequenceNum: UInt32, ageSeconds: UInt32) -> ShelfModeHistoryLog {
        ShelfModeHistoryLog(
            pumpTimeSec: basePumpTimeSec - ageSeconds,
            sequenceNum: sequenceNum,
            msecSinceReset: 0,
            lipoIbc: 0,
            lipoAbc: 0,
            lipoCurrent: 0,
            lipoRemCap: 0,
            lipoMv: 0
        )
    }

    /// Records a minute apart up to now, with a ShelfMode record at `shelfModeAt`.
    private func historyWithShelfMode(count: UInt32, shelfModeAt: UInt32) -> [HistoryLog] {
        (1 ... count).map { sequence -> HistoryLog in
            let age = (count - sequence) * 60
            return sequence == shelfModeAt ? shelfMode(sequenceNum: sequence, ageSeconds: age) : log(sequenceNum: sequence, ageSeconds: age)
        }
    }

    func testTheWalkStopsAtShelfModeAndSavesItsFloor() throws {
        setPumpSerial()
        // The lookback reaches record 180; the ShelfMode record sits above it, inside the first deep slice.
        stubHistory(serving: historyWithShelfMode(count: 600, shelfModeAt: 300))

        let outcome = try XCTUnwrap(runTick())

        XCTAssertEqual(manager.state.historyBackfill?.undatableThroughSequenceNum, 300)
        XCTAssertEqual(outcome.bookkeeping.undatableThroughSequenceNum, 300)
        XCTAssertTrue(outcome.isDeepBackfillComplete)
        XCTAssertTrue(outcome.reachesPumpStart)
        XCTAssertEqual(outcome.reportableRange, 301 ... 600)
        XCTAssertEqual(requestedRanges().count, 2, "the slice that read the ShelfMode record was the last: \(requestedRanges())")
    }

    func testAfterARelaunchNothingAtOrBelowTheShelfModeRecordIsRead() throws {
        setPumpSerial()
        let history = historyWithShelfMode(count: 600, shelfModeAt: 300)
        stubHistory(serving: history)
        _ = try XCTUnwrap(runTick())

        manager = TandemPumpManager(state: manager.state, bluetooth: bluetooth)
        coordinator = HistoryBackfillCoordinator(pumpManager: manager)
        bluetooth.resetRecordedTraffic()
        stubHistory(serving: history)
        let outcome = try XCTUnwrap(runTick())

        XCTAssertFalse(requestedRanges().isEmpty)
        XCTAssertTrue(requestedRanges().allSatisfy { $0.lowerBound > 300 }, "read \(requestedRanges())")
        XCTAssertEqual(outcome.reportableRange?.lowerBound, 301)
        XCTAssertTrue(outcome.isDeepBackfillComplete)
    }

    func testAShelfModeRecordBelowTheLookbackIsNeverRead() throws {
        setPumpSerial()
        stubHistory(serving: historyWithShelfMode(count: 600, shelfModeAt: 20))

        let outcome = try XCTUnwrap(runTick())

        XCTAssertNil(manager.state.historyBackfill?.undatableThroughSequenceNum)
        XCTAssertTrue(outcome.isDeepBackfillComplete)
        XCTAssertTrue(requestedRanges().allSatisfy { $0.lowerBound > 20 })
    }

    // MARK: - Floors

    /// The regression this whole separation exists for.
    ///
    /// Trio's `startDateToFilterNewPumpEvents` is `lastEventDate - 15min`, and this driver
    /// reports basal and bolus status stamped ≈now on every sync — so within one cycle of a pump
    /// being added, the host's floor sits minutes in the past. If that date bounded the walk,
    /// the backfill would declare itself finished before reading any of the insulin still
    /// acting, and IOB would be short by however much was delivered before the app arrived.
    func testHostFloorDoesNotBoundTheWalkOrRatchetTheStoredFloor() throws {
        setPumpSerial()
        let now = Date()
        manager.delegateQueue = DispatchQueue(label: "history-backfill-floor-test")
        let delegate = MockPumpManagerDelegate()
        delegate.startDateToFilterNewPumpEvents = now.addingTimeInterval(-.minutes(15))
        manager.pumpManagerDelegate = delegate
        manager.state.bolusReportLedger = BolusReportLedger(trackingSince: .distantPast)

        stubStatus(first: 1, last: 5000)
        stubHistoryStream(secondsPerSequence: secondsPerSequence(spanning: 1000), newestSequenceNum: 5000)

        let outcome = try XCTUnwrap(runTick(now: now))

        XCTAssertEqual(
            try XCTUnwrap(outcome.bookkeeping.firstSeenFloor).timeIntervalSince(now),
            -HistoryBackfillPlanner.deepFetchLookback,
            accuracy: 1,
            "The stored floor stays where the pump was first seen; the host's advancing date must not ratchet it"
        )
        XCTAssertEqual(
            manager.state.historyBackfill?.firstSeenFloor,
            outcome.bookkeeping.firstSeenFloor,
            "and what is persisted is that same floor"
        )

        // A walk bounded by the host's floor would have stopped inside the newest slice.
        let covered = try XCTUnwrap(outcome.sessionCovered)
        XCTAssertLessThanOrEqual(covered.lowerBound, 5000 - HistoryBackfillPlanner.maxDeepSliceSize)

        // Nor does it bound reporting: a pump-UI bolus found one sync late sits below it (#345).
        XCTAssertLessThan(outcome.emitFloor, delegate.startDateToFilterNewPumpEvents)
    }

    // MARK: - Pump identity

    /// A replacement pump's bookkeeping is discarded: its sequence numbers describe its own
    /// history, and its pre-existing log may predate entering service.
    func testReplacementPumpStartsOverWithAFloorAtFirstSight() throws {
        let now = Date()
        var state = Self.backfillEnabledState()
        state.pumpState.pumpSerial = 999
        state.historyBackfill = HistoryBackfillState(
            pumpSerial: Self.pumpSerial,
            watermark: 900,
            firstSeenFloor: .distantPast
        )
        manager = TandemPumpManager(state: state, bluetooth: bluetooth)
        coordinator = HistoryBackfillCoordinator(pumpManager: manager)

        stubStatus(first: 1, last: 910)
        stubHistoryStream(secondsPerSequence: secondsPerSequence(spanning: 600), newestSequenceNum: 910)

        let outcome = try XCTUnwrap(runTick(now: now))

        XCTAssertEqual(outcome.bookkeeping.pumpSerial, 999)
        XCTAssertEqual(
            outcome.bookkeeping.firstSeenFloor?.timeIntervalSince(now),
            -HistoryBackfillPlanner.deepFetchLookback,
            "The old pump's floor is discarded; only this pump's still-acting insulin is imported"
        )
        XCTAssertEqual(
            requestedStartLogs().first,
            910,
            "The old watermark must not be trusted; the read restarts from the newest entry"
        )
        XCTAssertEqual(outcome.bookkeeping.watermark, 910)
    }

    /// A pump whose log was erased restarts its counter below the watermark. Left alone, the
    /// watermark reads as "nothing new to fetch" against every later status — so the driver
    /// would silently never read another entry from this pump.
    func testErasedLogResetsTheWatermarkAndRereadsThePump() throws {
        let now = Date()
        let floor = now.addingTimeInterval(-.hours(3))
        var state = Self.backfillEnabledState()
        state.pumpState.pumpSerial = Self.pumpSerial
        state.historyBackfill = HistoryBackfillState(
            pumpSerial: Self.pumpSerial,
            watermark: 900,
            firstSeenFloor: floor
        )
        manager = TandemPumpManager(state: state, bluetooth: bluetooth)
        coordinator = HistoryBackfillCoordinator(pumpManager: manager)

        // Entries filed under the old numbering, which now names different entries entirely.
        try manager.historyLogStore.insert(
            (1 ... 10).map { log(sequenceNum: $0) },
            pumpSerial: Self.pumpSerial
        )

        // The pump now holds far less than has already been read from it.
        stubStatus(first: 1, last: 50)
        stubHistoryStream()

        let outcome = try XCTUnwrap(runTick(now: now))

        XCTAssertEqual(outcome.bookkeeping.watermark, 50, "The stale read position is dropped and re-established")
        XCTAssertEqual(
            outcome.bookkeeping.firstSeenFloor, floor,
            "Same pump, same service: only the read position was meaningless"
        )
        XCTAssertEqual(requestedStartLogs().first, 50, "The pump is read again from its newest entry")
        XCTAssertEqual(outcome.sessionCovered, 1 ... 50)
        XCTAssertEqual(
            try manager.historyLogStore.count(pumpSerial: Self.pumpSerial), 50,
            "Records filed under the old numbering are cleared rather than mixed with the new"
        )
    }

    /// faketandem answers an empty log with numEntries 0 and the range 0...0, which names no
    /// entry: a read of it waited out the chunk timeout twice, 18 s a tick.
    func testEmptyLogIsBookkeptAsReadWithoutARequest() throws {
        setPumpSerial()
        bluetooth.stub(HistoryLogStatusRequest.self, with: HistoryLogStatusResponse(
            numEntries: 0, firstSequenceNum: 0, lastSequenceNum: 0
        ))

        let outcome = try XCTUnwrap(runTick())

        XCTAssertTrue(bluetooth.sent(HistoryLogRequest.self).isEmpty)
        XCTAssertEqual(outcome.rangesRead, [0 ... 0])
        XCTAssertEqual(outcome.sessionCovered, 0 ... 0)
        XCTAssertEqual(outcome.bookkeeping.watermark, 0)
        XCTAssertEqual(outcome.pumpSequenceRange, 0 ... 0)
        XCTAssertTrue(outcome.isDeepBackfillComplete, "The pump holds nothing older to walk to")
        XCTAssertEqual(manager.state.historyBackfill, outcome.bookkeeping)
    }

    func testErasedLogLeftEmptyDropsTheWatermarkAndTheStoreWithoutARead() throws {
        var state = Self.backfillEnabledState()
        state.pumpState.pumpSerial = Self.pumpSerial
        state.historyBackfill = HistoryBackfillState(pumpSerial: Self.pumpSerial, watermark: 900)
        manager = TandemPumpManager(state: state, bluetooth: bluetooth)
        coordinator = HistoryBackfillCoordinator(pumpManager: manager)
        try manager.historyLogStore.insert((1 ... 10).map { log(sequenceNum: $0) }, pumpSerial: Self.pumpSerial)
        bluetooth.stub(HistoryLogStatusRequest.self, with: HistoryLogStatusResponse(
            numEntries: 0, firstSequenceNum: 0, lastSequenceNum: 0
        ))

        let outcome = try XCTUnwrap(runTick())

        XCTAssertTrue(bluetooth.sent(HistoryLogRequest.self).isEmpty)
        XCTAssertEqual(outcome.bookkeeping.watermark, 0)
        XCTAssertEqual(try manager.historyLogStore.count(pumpSerial: Self.pumpSerial), 0)
    }

    // MARK: - Feature flags

    func testAFreshInstallReadsHistory() throws {
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        coordinator = HistoryBackfillCoordinator(pumpManager: manager)
        setPumpSerial()
        stubStatus(first: 1, last: 10)
        stubHistoryStream()

        let outcome = try XCTUnwrap(runTick())

        XCTAssertEqual(outcome.rangesRead, [1 ... 10])
    }

    /// Off means nothing at all — not even the status read a plan is derived from.
    func testNoHistoryIsReadWhileTheBackfillFlagIsOff() {
        manager.state.featureFlags[.historyBackfill] = false
        setPumpSerial()
        stubStatus(first: 1, last: 10)
        stubHistoryStream()

        XCTAssertNil(runTick())

        XCTAssertTrue(bluetooth.sentMessages.isEmpty, "Not even the history log status is read")
        XCTAssertNil(manager.state.historyBackfill, "No bookkeeping is persisted")
        XCTAssertEqual(try? manager.historyLogStore.count(pumpSerial: Self.pumpSerial), 0)
    }

    /// Turning it on later must read everything, not resume from a watermark written while off.
    func testTurningTheFlagOnReadsTheHistoryItSkipped() throws {
        manager.state.featureFlags[.historyBackfill] = false
        setPumpSerial()
        stubStatus(first: 1, last: 10)
        stubHistoryStream()
        _ = runTick()

        manager.state.featureFlags[.historyBackfill] = true
        let outcome = try XCTUnwrap(runTick())

        XCTAssertEqual(outcome.rangesRead, [1 ... 10])
        XCTAssertEqual(outcome.bookkeeping.watermark, 10)
        XCTAssertEqual(try manager.historyLogStore.count(pumpSerial: Self.pumpSerial), 10)
    }

    /// Dose reporting is a separate switch, and it does not gate the reading.
    func testTheBackfillReadsWithDoseReportingOff() throws {
        manager.state.featureFlags[.historyDoseReporting] = false
        setPumpSerial()
        stubStatus(first: 1, last: 10)
        stubHistoryStream()

        let outcome = try XCTUnwrap(runTick())

        XCTAssertEqual(outcome.rangesRead, [1 ... 10], "Reading is unaffected by the reporting flag")
    }

    /// Reporting means nothing without the read that produces something to report.
    func testDoseReportingStaysOffWithoutTheBackfill() {
        var flags = TandemFeatureFlags()
        flags[.historyBackfill] = false
        flags[.historyDoseReporting] = true

        XCTAssertFalse(flags.historyDoseReporting, "Needs History Backfill on as well")

        flags[.historyBackfill] = true
        XCTAssertTrue(flags.historyDoseReporting)
    }

    // MARK: - Ownership

    /// The manager owns a coordinator, which owns a fetcher. A strong reference from the fetcher
    /// back to the manager closes that loop, and the manager — with the whole BLE stack behind
    /// it — outlives the user deleting the pump.
    func testDeletingThePumpReleasesTheManager() {
        weak var released: TandemPumpManager?

        do {
            let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: StubPumpBluetooth())
            released = manager
            // Touching the lazy coordinator is what builds the manager → coordinator → fetcher
            // chain the cycle would have run back along.
            _ = manager.historyBackfillCoordinator
        }

        XCTAssertNil(released, "The pump manager must not be kept alive by its own history fetcher")
    }

    // MARK: - Sharing the history stream

    /// Two fetches at once would each count the other's entries off the shared stream. A tick
    /// that finds the gate held steps aside and leaves the bookkeeping untouched.
    func testTickIsSkippedWhileAnotherReaderHoldsTheHistoryStream() {
        setPumpSerial()
        stubStatus(first: 1, last: 10)
        stubHistoryStream()

        XCTAssertTrue(manager.historyFetchGate.tryAcquire())
        defer { manager.historyFetchGate.release() }

        XCTAssertNil(runTick())
        XCTAssertNil(manager.state.historyBackfill)
        XCTAssertTrue(bluetooth.sent(HistoryLogRequest.self).isEmpty)
    }

    /// A fetcher that loses the gate reports `.busy` rather than returning silently, so a caller
    /// sequencing several ranges is not left waiting on a completion that never fires.
    func testFetcherReportsBusyWhenTheGateIsHeld() {
        setPumpSerial()
        stubStatus(first: 1, last: 10)
        stubHistoryStream()

        XCTAssertTrue(manager.historyFetchGate.tryAcquire())
        defer { manager.historyFetchGate.release() }

        var result: Result<HistoryLogFetcher.Progress, HistoryLogFetcher.FetchError>?
        let expectation = expectation(description: "fetch reports busy")
        HistoryLogFetcher(pumpManager: manager).start(numberOfLogs: 10) {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10.0)

        guard case .failure(.busy) = result else {
            return XCTFail("Expected .busy, got \(String(describing: result))")
        }
    }

    func testGateIsReleasedAfterATick() throws {
        setPumpSerial()
        stubStatus(first: 1, last: 10)
        stubHistoryStream()

        _ = try XCTUnwrap(runTick())

        XCTAssertFalse(manager.historyFetchGate.isBusy)
    }
}
