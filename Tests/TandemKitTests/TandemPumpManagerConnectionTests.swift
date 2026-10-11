import LoopKit
@testable import TandemKit
import XCTest

/// Every pump command funnels through `ensureConnected`, which brings the link up (or reports that
/// it could not) before the command's blocking writes run. These tests pin what the driver does on
/// each side of that gate: nothing is written when the link is down, and the caller still gets
/// exactly one result.
@available(macOS 13.0, iOS 14.0, *) final class TandemPumpManagerConnectionTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    // Held here: the manager's reference to its delegate is weak.
    private var delegate: MockPumpManagerDelegate?

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
    }

    override func tearDown() {
        manager = nil
        bluetooth = nil
        delegate = nil
        super.tearDown()
    }

    private func stubSyncResponses() {
        bluetooth.stub(ApiVersionRequest.self, with: ApiVersionResponse(majorVersion: 3, minorVersion: 4))
        bluetooth.stub(InsulinStatusRequest.self, with: InsulinStatusResponse(
            currentInsulinAmount: 150,
            isEstimate: 0,
            insulinLowAmount: 0
        ))
        bluetooth.stub(
            CurrentBatteryV1Request.self,
            with: CurrentBatteryV1Response(currentBatteryAbc: 20, currentBatteryIbc: 80)
        )
    }

    // MARK: - Connect failures

    func testSyncDoesNotWriteWhenConnectFails() {
        bluetooth.connectError = PumpCommError.pumpNotConnected
        stubSyncResponses()

        let expectation = expectation(description: "syncPumpData completes")
        var reportedLastSync: Date?
        var completionCount = 0
        manager.syncPumpData { lastSync in
            reportedLastSync = lastSync
            completionCount += 1
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(bluetooth.ensureConnectedCount, 1)
        XCTAssertTrue(bluetooth.sentMessages.isEmpty, "Nothing should be written while disconnected")
        XCTAssertNil(reportedLastSync, "Never-synced state must not report a lastSync it does not have")
        XCTAssertEqual(completionCount, 1, "The loop must get exactly one result")
    }

    /// A failed sync must report the *previous* lastSync, not `nil` and not `now` — Loop uses it to
    /// decide how far back its insulin delivery data can be trusted.
    func testFailedSyncReportsPreviousLastSync() {
        let previousSync = Date().addingTimeInterval(-2 * 60 * 60)
        manager.state.lastReconciliation = previousSync
        bluetooth.connectError = PumpCommError.pumpNotConnected

        let expectation = expectation(description: "syncPumpData completes")
        var reportedLastSync: Date?
        manager.syncPumpData { lastSync in
            reportedLastSync = lastSync
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(reportedLastSync, previousSync)
        XCTAssertEqual(manager.state.lastReconciliation, previousSync, "A failed sync must not advance lastReconciliation")
    }

    func testEnactBolusReportsCommunicationErrorWhenConnectFails() {
        bluetooth.connectError = PumpCommError.pumpNotConnected

        let expectation = expectation(description: "enactBolus completes")
        var reportedError: PumpManagerError?
        manager.enactBolus(units: 1.0, activationType: .manualNoRecommendation) { error in
            reportedError = error
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        guard case .communication = reportedError else {
            return XCTFail("Expected a communication error, got \(String(describing: reportedError))")
        }
        XCTAssertFalse(
            bluetooth.didSend(BolusPermissionRequest.self),
            "No bolus permission should be requested while disconnected"
        )
    }

    // MARK: - Successful sync

    func testSuccessfulSyncAdvancesLastReconciliation() {
        stubSyncResponses()
        // The remaining reads are unstubbed on purpose: each one logs and returns early, which is
        // the behaviour a partially-responsive pump produces. The sync must still complete.
        let expectation = expectation(description: "syncPumpData completes")
        var reportedLastSync: Date?
        manager.syncPumpData { lastSync in
            reportedLastSync = lastSync
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(bluetooth.ensureConnectedCount, 1)
        XCTAssertNotNil(reportedLastSync)
        XCTAssertEqual(reportedLastSync, manager.state.lastReconciliation)
    }

    /// A session can stay up at the link layer while every read times out. `lastSync` is Loop's
    /// measure of how far back its insulin data can be trusted, so a sync the pump answered nothing
    /// to must not advance it.
    func testSyncThePumpAnswersNothingToDoesNotAdvanceLastSync() {
        let previousSync = Date().addingTimeInterval(-2 * 60 * 60)
        manager.state.lastReconciliation = previousSync
        // No stubs registered: the link is up and every read returns nil, as a wedged session does.

        let expectation = expectation(description: "syncPumpData completes")
        var reportedLastSync: Date?
        manager.syncPumpData { lastSync in
            reportedLastSync = lastSync
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertFalse(bluetooth.sentMessages.isEmpty, "The sync should still have tried to read")
        XCTAssertEqual(manager.state.lastReconciliation, previousSync)
        XCTAssertEqual(reportedLastSync, previousSync)
    }

    /// The settings re-read is stamped for 24 hours, so stamping it after a silent pump would hide
    /// the failure for a day.
    func testSyncThePumpAnswersNothingToDoesNotStampTheSettingsCheck() {
        let expectation = expectation(description: "syncPumpData completes")
        manager.syncPumpData { _ in expectation.fulfill() }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertNil(manager.state.lastSettingsCheckedAt)
    }

    /// One answer is enough: a partially responsive pump has still been reconciled with.
    func testSyncAdvancesLastSyncOnASingleResponse() {
        let previousSync = Date().addingTimeInterval(-2 * 60 * 60)
        manager.state.lastReconciliation = previousSync
        bluetooth.stub(InsulinStatusRequest.self, with: InsulinStatusResponse(
            currentInsulinAmount: 150,
            isEstimate: 0,
            insulinLowAmount: 0
        ))

        let expectation = expectation(description: "syncPumpData completes")
        manager.syncPumpData { _ in expectation.fulfill() }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertNotEqual(manager.state.lastReconciliation, previousSync)
    }

    // MARK: - Not stacking up

    /// A sync against an unresponsive pump holds the command queue for about as long as Loop's poll
    /// interval, so polls that stack up behind it put every user command — a bolus included — in a
    /// queue minutes deep.
    func testAutomaticPollStandsDownWhileASyncIsAlreadyRunning() {
        manager.state.lastReconciliation = Date().addingTimeInterval(-60 * 60)
        stubSyncResponses()

        var polled = false
        bluetooth.onWrite = { [weak self] _ in
            // Runs while the outer sync still holds the queue. Guarded so an unguarded poll shows
            // up as one extra sync rather than as runaway recursion.
            guard !polled, let self else { return }
            polled = true
            self.manager.ensureCurrentPumpData { _ in }
        }

        let synced = expectation(description: "syncPumpData completes")
        manager.syncPumpData { _ in synced.fulfill() }
        wait(for: [synced], timeout: 5.0)

        XCTAssertTrue(polled, "The poll should have been attempted from inside the sync")
        XCTAssertEqual(bluetooth.ensureConnectedCount, 1, "The poll must not queue a second sync")
    }

    /// Trio loops as soon as its poll completes, on whatever pump data it then holds.
    func testAPollThatStandsDownIsHandedTheRunningSyncsResult() {
        let stale = Date().addingTimeInterval(-60 * 60)
        manager.state.lastReconciliation = stale
        stubSyncResponses()

        var events: [String] = []
        var polledLastSync: Date??
        bluetooth.onWrite = { [weak self] _ in
            guard !events.contains("poll"), let self else { return }
            events.append("poll")
            self.manager.ensureCurrentPumpData { lastSync in
                events.append("poll completed")
                polledLastSync = lastSync
            }
        }

        let synced = expectation(description: "syncPumpData completes")
        manager.syncPumpData { _ in
            events.append("sync completed")
            synced.fulfill()
        }
        wait(for: [synced], timeout: 5.0)

        XCTAssertEqual(events, ["poll", "sync completed", "poll completed"])
        XCTAssertEqual(bluetooth.ensureConnectedCount, 1)
        let fresh = try? XCTUnwrap(manager.state.lastReconciliation)
        XCTAssertNotEqual(fresh, stale)
        XCTAssertEqual(polledLastSync, .some(fresh), "the running sync's result, not the stale one")
    }

    /// Only the automatic poll stands down. A sync the user asked for is not a duplicate of one
    /// already grinding through timeouts.
    func testAUserRequestedSyncRunsEvenWhileOneIsAlreadyRunning() {
        stubSyncResponses()

        var reSynced = false
        bluetooth.onWrite = { [weak self] _ in
            guard !reSynced, let self else { return }
            reSynced = true
            self.manager.syncPumpData { _ in }
        }

        let synced = expectation(description: "syncPumpData completes")
        manager.syncPumpData { _ in synced.fulfill() }
        wait(for: [synced], timeout: 5.0)

        XCTAssertEqual(bluetooth.ensureConnectedCount, 2)
    }

    /// The stand-down must not leave the flag set: the next poll after a sync finishes has to run.
    func testPollRunsAgainOnceTheEarlierSyncHasFinished() {
        manager.state.lastReconciliation = Date().addingTimeInterval(-60 * 60)
        stubSyncResponses()

        let first = expectation(description: "first sync completes")
        manager.syncPumpData { _ in first.fulfill() }
        wait(for: [first], timeout: 5.0)

        manager.state.lastReconciliation = Date().addingTimeInterval(-60 * 60)
        let second = expectation(description: "poll syncs")
        manager.ensureCurrentPumpData { _ in second.fulfill() }
        wait(for: [second], timeout: 5.0)

        XCTAssertEqual(bluetooth.ensureConnectedCount, 2)
    }

    /// `ensureCurrentPumpData` is Loop's periodic poll; it must not re-hit the pump when the last
    /// sync is still fresh.
    func testEnsureCurrentPumpDataSkipsRecentSync() {
        let recentSync = Date().addingTimeInterval(-60)
        manager.state.lastReconciliation = recentSync
        manager.state.isConnected = true

        let expectation = expectation(description: "ensureCurrentPumpData completes")
        var reportedLastSync: Date?
        manager.ensureCurrentPumpData { lastSync in
            reportedLastSync = lastSync
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(reportedLastSync, recentSync)
        XCTAssertEqual(bluetooth.ensureConnectedCount, 0, "A fresh sync should not touch the pump")
    }

    func testEnsureCurrentPumpDataSyncsWhenStale() {
        manager.state.lastReconciliation = Date().addingTimeInterval(-60 * 60)
        stubSyncResponses()

        let expectation = expectation(description: "ensureCurrentPumpData completes")
        manager.ensureCurrentPumpData { _ in expectation.fulfill() }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(bluetooth.ensureConnectedCount, 1)
    }

    // MARK: - Automatic reconnect

    @discardableResult
    private func attachDelegate() -> (MockPumpManagerDelegate, DispatchQueue) {
        let delegate = MockPumpManagerDelegate()
        let queue = DispatchQueue(label: "connection-test-delegate")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = queue
        queue.sync {}
        self.delegate = delegate
        return (delegate, queue)
    }

    /// The pump's qualifying events go nowhere while the link is down (#351).
    func testAnAutomaticReconnectSyncsAndReportsAFreshBoundary() {
        let (delegate, queue) = attachDelegate()
        stubSyncResponses()
        // Inside the poll's throttle, which the reconnect does not wait out.
        let beforeTheDrop = Date().addingTimeInterval(-60)
        manager.state.lastReconciliation = beforeTheDrop
        manager.state.isConnected = true

        manager.didReconnectAutomatically()
        queue.sync {}

        XCTAssertEqual(bluetooth.ensureConnectedCount, 1)
        XCTAssertTrue(bluetooth.didSend(InsulinStatusRequest.self))
        let boundary = try? XCTUnwrap(manager.state.lastReconciliation)
        XCTAssertGreaterThan(boundary ?? .distantPast, beforeTheDrop)
        XCTAssertEqual(delegate.pumpEventBatches.last?.lastReconciliation, boundary)
    }

    func testAnAutomaticReconnectBeforeTheHostAdoptsThePumpLeavesTheSyncToItsFirstPoll() {
        stubSyncResponses()

        manager.didReconnectAutomatically()

        XCTAssertEqual(bluetooth.ensureConnectedCount, 0)
        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
    }

    func testAnAutomaticReconnectDuringASyncDoesNotQueueAnother() {
        attachDelegate()
        stubSyncResponses()

        var reconnected = false
        bluetooth.onWrite = { [weak self] _ in
            guard !reconnected, let self else { return }
            reconnected = true
            self.manager.didReconnectAutomatically()
        }

        let synced = expectation(description: "syncPumpData completes")
        manager.syncPumpData { _ in synced.fulfill() }
        wait(for: [synced], timeout: 5.0)

        XCTAssertTrue(reconnected)
        XCTAssertEqual(bluetooth.ensureConnectedCount, 1)
    }

    /// A host poll that lands while the reconnect's sync runs doses on what that sync read.
    func testAPollDuringAReconnectsSyncIsHandedItsResult() {
        attachDelegate()
        stubSyncResponses()
        let stale = Date().addingTimeInterval(-60 * 60)
        manager.state.lastReconciliation = stale

        var polledLastSync: Date??
        bluetooth.onWrite = { [weak self] _ in
            guard polledLastSync == nil, let self else { return }
            polledLastSync = .some(nil)
            self.manager.ensureCurrentPumpData { polledLastSync = $0 }
        }

        manager.didReconnectAutomatically()

        XCTAssertEqual(bluetooth.ensureConnectedCount, 1)
        XCTAssertNotEqual(manager.state.lastReconciliation, stale)
        XCTAssertEqual(polledLastSync, .some(manager.state.lastReconciliation))
    }

    // MARK: - Teardown

    func testPrepareForDeactivationDeactivatesTransport() {
        let expectation = expectation(description: "prepareForDeactivation completes")
        manager.prepareForDeactivation { _ in expectation.fulfill() }

        wait(for: [expectation], timeout: 5.0)

        // deactivate() (not plain disconnect()) is what suppresses auto-reconnect and drops the
        // back-reference, so a deleted pump cannot reconnect and re-persist its state.
        XCTAssertEqual(bluetooth.deactivateCount, 1)
        XCTAssertEqual(bluetooth.disconnectCount, 1)
        XCTAssertNil(bluetooth.pumpManager)
    }
}
