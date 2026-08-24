import Combine
import Foundation
import LoopKit
@testable import TandemKit
import XCTest

/// Drives the sync-driven history backfill orchestration against a stub pump: emit-floor seeding,
/// the deep backward walk, the per-sync window cap, incremental catch-up, and the persisted
/// bookkeeping that lets an interrupted backfill resume.
@available(macOS 13.0, iOS 14.0, *) final class TandemPumpManagerHistoryBackfillTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!

    private static let pumpSerial: UInt32 = 123_456

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        delegate = MockPumpManagerDelegate()
    }

    override func tearDown() {
        manager = nil
        bluetooth = nil
        delegate = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func attachDelegate() {
        manager.delegateQueue = DispatchQueue(label: "history-backfill-test")
        manager.pumpManagerDelegate = delegate
    }

    private func setPumpSerial() {
        manager.state.pumpState.pumpSerial = Self.pumpSerial
    }

    /// A recent pump-clock base for generated entries. Timestamps must be inside the retention
    /// window, or the manager's store would prune them as they arrive.
    private lazy var nowPumpTimeSec = UInt32(Dates.fromInstantToJan12008EpochSeconds(Date()))

    /// An entry stamped `age` in the past (must stay inside retention, or the store prunes it on
    /// arrival), so a test can place the backfill's time boundaries partway down pump history.
    private func log(sequenceNum: UInt32, age: TimeInterval = 0) -> BolusActivatedHistoryLog {
        BolusActivatedHistoryLog(
            pumpTimeSec: nowPumpTimeSec - UInt32(age),
            sequenceNum: sequenceNum,
            bolusId: Int(sequenceNum),
            selectedIob: 0,
            iob: 0,
            bolusSize: 1.0
        )
    }

    private func stubStatus(first: UInt32, last: UInt32) {
        bluetooth.stub(HistoryLogStatusRequest.self, with: HistoryLogStatusResponse(
            numEntries: last - first + 1,
            firstSequenceNum: first,
            lastSequenceNum: last
        ))
    }

    /// Acknowledges every `HistoryLogRequest` and streams back the entries it asked for, the way
    /// the pump does: the ack comes from the write, the entries arrive as notifications.
    private func stubHistoryStream(
        streamId: Int = 7,
        ageFor: @escaping (UInt32) -> TimeInterval = { _ in 0 }
    ) {
        bluetooth.stub(HistoryLogRequest.self, with: HistoryLogResponse(status: 0, streamId: streamId))

        bluetooth.onWrite = { [weak self] message in
            guard let self, let request = message as? HistoryLogRequest else { return }

            let top = Int(request.startLog)
            let bottom = max(0, top - max(request.numberOfLogs, 1) + 1)

            let logs = stride(from: top, through: bottom, by: -1)
                .map { self.log(sequenceNum: UInt32($0), age: ageFor(UInt32($0))) }

            guard !logs.isEmpty else { return }

            self.manager.historyLogStream.send(HistoryLogStreamResponse(
                numberOfHistoryLogs: logs.count,
                streamId: streamId,
                historyLogStreamBytes: logs.map(\.cargo)
            ))
        }
    }

    /// Starts one fire-and-forget backfill pass and spins the main run loop until the pass
    /// releases itself. Each fetch window burns real wall-clock time inside HistoryLogFetcher
    /// (post-request delay plus polling), so the timeout is generous.
    private func runBackfillPass(timeout: TimeInterval = 60, file: StaticString = #filePath, line: UInt = #line) {
        manager.fetchAndLogPumpHistory()
        waitUntil(timeout: timeout, file: file, line: line) {
            self.manager.historyBackfillLock.lock()
            defer { self.manager.historyBackfillLock.unlock() }
            return !self.manager.historyBackfillInFlight
        }
    }

    private func waitUntil(
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTFail("Timed out waiting for the backfill pass to finish", file: file, line: line)
    }

    // MARK: - Emit floor

    func testEmitFloorSeededOnceFromDelegate() {
        attachDelegate()
        let boundary = Date(timeIntervalSinceReferenceDate: 700_000_000)
        delegate.startDateToFilterNewPumpEvents = boundary

        XCTAssertTrue(manager.establishHistoryEmitFloorIfNeeded())
        XCTAssertEqual(manager.state.historyEmitFloor, boundary)

        let decoded = TandemPumpManagerState(rawValue: manager.state.rawValue)
        XCTAssertEqual(decoded.historyEmitFloor, boundary)

        // The live boundary advances whenever a commanded dose finalizes; a second read must not
        // raise the floor past pump-UI doses that have yet to be reported.
        delegate.startDateToFilterNewPumpEvents = boundary.addingTimeInterval(.hours(6))
        XCTAssertTrue(manager.establishHistoryEmitFloorIfNeeded())
        XCTAssertEqual(manager.state.historyEmitFloor, boundary)
    }

    func testEmitFloorIsDeferredWithoutDelegate() {
        XCTAssertFalse(manager.establishHistoryEmitFloorIfNeeded())
        XCTAssertNil(manager.state.historyEmitFloor)
    }

    // MARK: - Preconditions

    func testBackfillNoOpsWithoutPumpSerial() {
        manager.state.historyEmitFloor = Date()
        stubStatus(first: 1, last: 10)
        stubHistoryStream()

        runBackfillPass(timeout: 5)

        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
    }

    func testBackfillNoOpsWithoutEmitFloor() {
        setPumpSerial()
        stubStatus(first: 1, last: 10)
        stubHistoryStream()

        runBackfillPass(timeout: 5)

        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
    }

    // MARK: - Deep backfill

    func testDeepBackfillFetchesEntireRecentHistory() throws {
        setPumpSerial()
        attachDelegate() // Boundary defaults to .distantPast, so the 24h window bounds the target.
        XCTAssertTrue(manager.establishHistoryEmitFloorIfNeeded())
        stubStatus(first: 1, last: 30)
        stubHistoryStream()

        runBackfillPass()

        XCTAssertNotNil(manager.state.historyBackfillCompletedAt)
        XCTAssertEqual(manager.state.historyLastFetchedSequenceNum, 30)
        XCTAssertEqual(try manager.historyLogStore.count(pumpSerial: Self.pumpSerial), 30)
        XCTAssertEqual(try manager.historyLogStore.oldest(pumpSerial: Self.pumpSerial)?.sequenceNum, 1)
    }

    func testDeepBackfillStopsAtEmitFloorTarget() throws {
        setPumpSerial()
        attachDelegate()
        delegate.startDateToFilterNewPumpEvents = Date().addingTimeInterval(-.hours(1))
        XCTAssertTrue(manager.establishHistoryEmitFloorIfNeeded())
        // Entries below 346 are days older than the floor. Window 1 covers [346, 600] (recent);
        // window 2 covers [91, 345] and crosses the target, so the walk must stop there.
        stubStatus(first: 0, last: 600)
        stubHistoryStream { $0 < 346 ? .days(3) : 0 }

        runBackfillPass()

        XCTAssertNotNil(manager.state.historyBackfillCompletedAt)
        XCTAssertEqual(try manager.historyLogStore.oldest(pumpSerial: Self.pumpSerial)?.sequenceNum, 91)
        let requests = bluetooth.sent(HistoryLogRequest.self)
        XCTAssertFalse(requests.isEmpty)
        XCTAssertTrue(
            requests.allSatisfy { Int($0.startLog) - $0.numberOfLogs + 1 >= 91 },
            "No request may reach below the window that crossed the target"
        )
    }

    func testDeepBackfillHonorsWindowCapAndResumes() throws {
        setPumpSerial()
        attachDelegate() // .distantPast boundary, so the 24h window bounds the target.
        XCTAssertTrue(manager.establishHistoryEmitFloorIfNeeded())
        // Window 1 [4746, 5000] is recent; the walk clears the 6h priority boundary on window 2
        // (12h-old entries), after which the cap paces the background tail: 8 windows walk the
        // frontier from 5000 down to 2961. Everything below that is older than the 24h target,
        // so the resumed pass terminates after a single further window.
        stubStatus(first: 0, last: 5000)
        stubHistoryStream { seq in
            if seq >= 4746 { return 0 }
            if seq >= 2961 { return .hours(12) }
            return .days(3)
        }

        runBackfillPass()

        XCTAssertNil(manager.state.historyBackfillCompletedAt, "The capped pass must stay incomplete")
        XCTAssertEqual(manager.state.historyLastFetchedSequenceNum, 5000)
        XCTAssertEqual(try manager.historyLogStore.oldest(pumpSerial: Self.pumpSerial)?.sequenceNum, 2961)
        let firstPassRequests = bluetooth.sent(HistoryLogRequest.self)
        XCTAssertEqual(firstPassRequests.count, TandemPumpManager.historyBackfillMaxWindowsPerSync)

        runBackfillPass()

        XCTAssertNotNil(manager.state.historyBackfillCompletedAt)
        let resumedRequests = bluetooth.sent(HistoryLogRequest.self).dropFirst(firstPassRequests.count)
        XCTAssertEqual(
            resumedRequests.first?.startLog, 2960,
            "The resumed pass must continue below the previous frontier"
        )
    }

    /// The window cap must never starve the IOB-relevant hours: while the walk's oldest entry is
    /// still inside the priority window, a single pass keeps going past the cap.
    func testDeepBackfillIgnoresWindowCapInsidePriorityWindow() throws {
        setPumpSerial()
        attachDelegate()
        XCTAssertTrue(manager.establishHistoryEmitFloorIfNeeded())
        // 2300 recent entries need 10 windows — more than the cap — and never clear the 6h
        // priority boundary, so one pass fetches all of them (terminating at the start of pump
        // history) instead of pausing after 8.
        stubStatus(first: 1, last: 2300)
        stubHistoryStream()

        runBackfillPass(timeout: 90)

        XCTAssertNotNil(manager.state.historyBackfillCompletedAt)
        XCTAssertEqual(try manager.historyLogStore.oldest(pumpSerial: Self.pumpSerial)?.sequenceNum, 1)
        XCTAssertGreaterThan(
            bluetooth.sent(HistoryLogRequest.self).count,
            TandemPumpManager.historyBackfillMaxWindowsPerSync,
            "The pass must not pause at the cap while inside the priority window"
        )
    }

    // MARK: - Incremental catch-up

    func testIncrementalFetchRequestsOnlyEntriesAboveWatermark() throws {
        setPumpSerial()
        manager.state.historyEmitFloor = Date().addingTimeInterval(-.hours(1))
        manager.state.historyBackfillCompletedAt = Date()
        manager.state.historyLastFetchedSequenceNum = 100
        stubStatus(first: 1, last: 110)
        stubHistoryStream()

        runBackfillPass()

        let requests = bluetooth.sent(HistoryLogRequest.self)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.startLog, 110)
        XCTAssertEqual(requests.first?.numberOfLogs, 10)
        XCTAssertEqual(manager.state.historyLastFetchedSequenceNum, 110)

        // Now up to date: a further pass costs a status read and no chunk request.
        runBackfillPass()

        XCTAssertEqual(bluetooth.sent(HistoryLogRequest.self).count, 1)
        XCTAssertEqual(manager.state.historyLastFetchedSequenceNum, 110)
    }

    func testIncrementalDetectsPumpHistoryReset() {
        setPumpSerial()
        manager.state.historyEmitFloor = Date().addingTimeInterval(-.hours(1))
        manager.state.historyBackfillCompletedAt = Date()
        manager.state.historyLastFetchedSequenceNum = 500
        stubStatus(first: 1, last: 110)
        stubHistoryStream()

        runBackfillPass()

        XCTAssertNil(manager.state.historyLastFetchedSequenceNum)
        XCTAssertNil(manager.state.historyBackfillCompletedAt, "A reset pump must re-run the deep backfill")
        XCTAssertTrue(bluetooth.sent(HistoryLogRequest.self).isEmpty)
    }

    // MARK: - State persistence

    func testBackfillStateRoundTrip() {
        var state = TandemPumpManagerState(rawValue: [:])
        XCTAssertNil(state.historyEmitFloor)
        XCTAssertNil(state.historyBackfillCompletedAt)
        XCTAssertNil(state.historyLastFetchedSequenceNum)

        state.historyEmitFloor = Date(timeIntervalSinceReferenceDate: 700_000_000)
        state.historyBackfillCompletedAt = Date(timeIntervalSinceReferenceDate: 700_003_600)
        state.historyLastFetchedSequenceNum = 987_654

        let decoded = TandemPumpManagerState(rawValue: state.rawValue)
        XCTAssertEqual(decoded.historyEmitFloor, state.historyEmitFloor)
        XCTAssertEqual(decoded.historyBackfillCompletedAt, state.historyBackfillCompletedAt)
        XCTAssertEqual(decoded.historyLastFetchedSequenceNum, 987_654)
    }
}
