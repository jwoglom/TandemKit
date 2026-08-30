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
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        coordinator = HistoryBackfillCoordinator(pumpManager: manager)
    }

    override func tearDown() {
        coordinator = nil
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// A recent pump-clock base: entries must be inside the retention window or the manager's
    /// store prunes them as they arrive.
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
        var state = TandemPumpManagerState(rawValue: [:])
        state.pumpState.pumpSerial = Self.pumpSerial
        state.historyBackfill = HistoryBackfillState(
            pumpSerial: Self.pumpSerial,
            watermark: 900,
            emitFloor: Date().addingTimeInterval(-.hours(1))
        )
        // A fresh manager, as after a relaunch: persisted state, empty in-memory store.
        manager = TandemPumpManager(state: state, bluetooth: bluetooth)
        coordinator = HistoryBackfillCoordinator(pumpManager: manager)

        stubStatus(first: 1, last: 910)
        stubHistoryStream()

        let outcome = try XCTUnwrap(runTick())

        XCTAssertEqual(
            requestedStartLogs(),
            [910],
            "Only the 10 entries written since the watermark, not the 800-900 span the empty session store lacks"
        )
        XCTAssertEqual(bluetooth.sent(HistoryLogRequest.self).first?.numberOfLogs, 10)
        XCTAssertEqual(outcome.bookkeeping.watermark, 910)
        XCTAssertEqual(outcome.sessionCovered, 901 ... 910)
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

    /// The walk backward is sliced: a first-run backfill of thousands of entries must not occupy
    /// the pump's command queue in one uninterruptible block.
    func testDeepBackfillWalksBackwardOneSlicePerTick() throws {
        setPumpSerial()
        let slice = HistoryBackfillPlanner.maxDeepSliceSize
        let last: UInt32 = 5000
        stubStatus(first: 1, last: last)
        stubHistoryStream()

        let first = try XCTUnwrap(runTick())
        XCTAssertEqual(first.sessionCovered, (last - slice + 1) ... last)
        XCTAssertFalse(first.isDeepBackfillComplete)

        bluetooth.resetRecordedTraffic()
        stubStatus(first: 1, last: last)
        stubHistoryStream()
        let second = try XCTUnwrap(runTick())

        XCTAssertEqual(second.sessionCovered, (last - 2 * slice + 1) ... last)
        XCTAssertEqual(second.rangesRead, [(last - 2 * slice + 1) ... (last - slice)])
        XCTAssertEqual(requestedStartLogs(), [last - slice])
    }

    /// Once this session's span reaches back past the target date the walk stops, however much
    /// older history the pump still holds.
    func testDeepBackfillStopsOnceTheTargetDateIsCovered() throws {
        setPumpSerial()
        let now = Date()
        // Age entries steeply enough that one slice reaches past the lookback boundary.
        let secondsPerSequence = UInt32(HistoryBackfillPlanner.deepFetchLookback / 100)
        stubStatus(first: 1, last: 5000)
        stubHistoryStream(secondsPerSequence: secondsPerSequence, newestSequenceNum: 5000)

        let first = try XCTUnwrap(runTick(now: now))
        XCTAssertFalse(first.isDeepBackfillComplete)

        bluetooth.resetRecordedTraffic()
        stubStatus(first: 1, last: 5000)
        stubHistoryStream(secondsPerSequence: secondsPerSequence, newestSequenceNum: 5000)
        let second = try XCTUnwrap(runTick(now: now))

        XCTAssertTrue(second.isDeepBackfillComplete)
        XCTAssertTrue(requestedStartLogs().isEmpty, "Nothing left to read once the target is covered")
    }

    // MARK: - Pump identity

    /// A replacement pump's bookkeeping is discarded: its sequence numbers describe its own
    /// history, and its pre-existing log may predate entering service.
    func testReplacementPumpStartsOverWithAFloorAtFirstSight() throws {
        let now = Date()
        var state = TandemPumpManagerState(rawValue: [:])
        state.pumpState.pumpSerial = 999
        state.historyBackfill = HistoryBackfillState(
            pumpSerial: Self.pumpSerial,
            watermark: 900,
            emitFloor: .distantPast
        )
        manager = TandemPumpManager(state: state, bluetooth: bluetooth)
        coordinator = HistoryBackfillCoordinator(pumpManager: manager)

        stubStatus(first: 1, last: 910)
        stubHistoryStream()

        let outcome = try XCTUnwrap(runTick(now: now))

        XCTAssertEqual(outcome.bookkeeping.pumpSerial, 999)
        XCTAssertEqual(
            outcome.bookkeeping.emitFloor?.timeIntervalSince(now),
            -HistoryBackfillPlanner.deepFetchLookback,
            "The old pump's floor is discarded; only this pump's still-acting insulin is imported"
        )
        XCTAssertEqual(
            requestedStartLogs(),
            [910],
            "The old watermark must not be trusted; the read restarts from the newest entry"
        )
        XCTAssertEqual(outcome.bookkeeping.watermark, 910)
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
