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

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
    }

    override func tearDown() {
        manager = nil
        bluetooth = nil
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

    /// `ensureCurrentPumpData` is Loop's periodic poll; it must not re-hit the pump when the last
    /// sync is still fresh.
    func testEnsureCurrentPumpDataSkipsRecentSync() {
        let recentSync = Date().addingTimeInterval(-60)
        manager.state.lastReconciliation = recentSync

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
