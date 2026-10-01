import CoreBluetooth
import Foundation
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class TandemKitTroubleshootConnectionViewModelTests: XCTestCase {
    private typealias ViewModel = TandemKitTroubleshootConnectionViewModel

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

    // MARK: - What the screen shows

    func testAnUnpairedPumpThatHasNeverConnectedShowsNothingSaved() {
        let viewModel = ViewModel(pumpManager: manager)

        XCTAssertNil(viewModel.savedPumpText)
        XCTAssertFalse(viewModel.isSavedPumpKnownToSystem)
        XCTAssertFalse(viewModel.isConnected)
        XCTAssertEqual(viewModel.connectionIssue, .pumpUnreachable)
        XCTAssertEqual(viewModel.lastConnectedText, "Never")
    }

    func testAPoweredOnRadioIsShownAsOn() {
        let viewModel = ViewModel(pumpManager: manager)

        XCTAssertTrue(viewModel.isBluetoothPoweredOn)
        XCTAssertEqual(viewModel.bluetoothStatusText, "On")
    }

    func testEveryOtherRadioStateIsNamedWithTheIssueItCauses() {
        let expected: [(CBManagerState, String, PumpConnectionIssue)] = [
            (.poweredOff, "Off", .bluetoothOff),
            (.unauthorized, "Not authorized", .bluetoothUnauthorized),
            (.unsupported, "Unsupported", .bluetoothUnavailable),
            (.resetting, "Resetting", .bluetoothUnavailable),
            (.unknown, "Unknown", .pumpUnreachable)
        ]
        let viewModel = ViewModel(pumpManager: manager)

        for (radioState, text, issue) in expected {
            bluetooth.bluetoothState = radioState
            viewModel.refresh()

            XCTAssertFalse(viewModel.isBluetoothPoweredOn, "CBManagerState(rawValue: \(radioState.rawValue))")
            XCTAssertEqual(viewModel.bluetoothStatusText, text, "CBManagerState(rawValue: \(radioState.rawValue))")
            XCTAssertEqual(viewModel.connectionIssue, issue, "CBManagerState(rawValue: \(radioState.rawValue))")
        }
    }

    func testAConnectedPumpThatSyncedRecentlyShowsNoIssueAndWhenItLastSynced() {
        let lastSync = Date()
        manager.state.isConnected = true
        manager.state.lastReconciliation = lastSync

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium

        let viewModel = ViewModel(pumpManager: manager)

        XCTAssertTrue(viewModel.isConnected)
        XCTAssertNil(viewModel.connectionIssue)
        XCTAssertEqual(viewModel.lastConnectedText, formatter.string(from: lastSync))
    }

    func testASavedPumpIsDescribedWithItsSerialNumber() {
        manager.state.pumpState.peripheralUuid = UUID().uuidString
        manager.state.pumpState.pumpSerial = 1_234_567

        let viewModel = ViewModel(pumpManager: manager)

        XCTAssertEqual(viewModel.savedPumpText, "Tandem Mobi · SN 1234567")
    }

    func testASavedPumpWhoseSerialNumberIsNotYetKnownIsStillDescribed() {
        manager.state.pumpState.peripheralUuid = UUID().uuidString

        let viewModel = ViewModel(pumpManager: manager)

        XCTAssertEqual(viewModel.savedPumpText, "Tandem Mobi")
    }

    func testWithoutACentralTheSavedPumpIsNotClaimedToBeKnownToTheSystem() {
        manager.state.pumpState.peripheralUuid = UUID().uuidString

        let viewModel = ViewModel(pumpManager: manager)

        XCTAssertNil(bluetooth.manager)
        XCTAssertTrue(viewModel.isBluetoothPoweredOn)
        XCTAssertFalse(viewModel.isSavedPumpKnownToSystem)
    }

    func testAStatusUpdateFromTheManagerRefreshesTheScreen() {
        let viewModel = ViewModel(pumpManager: manager)
        XCTAssertFalse(viewModel.isConnected)

        manager.state.isConnected = true
        manager.state.lastReconciliation = Date()
        manager.notifyDelegateStateUpdated()
        drainMainQueue(hops: 2)

        XCTAssertTrue(viewModel.isConnected)
        XCTAssertNil(viewModel.connectionIssue)
    }

    // MARK: - Reconnecting

    func testAFailedReconnectSaysSoAndPointsToTheSteps() {
        bluetooth.connectError = PumpCommError.pumpNotConnected
        let viewModel = ViewModel(pumpManager: manager)

        viewModel.attemptReconnect()
        XCTAssertTrue(viewModel.isAttemptingReconnect)
        drainMainQueue()

        XCTAssertFalse(viewModel.isAttemptingReconnect)
        XCTAssertFalse(viewModel.isConnected)
        XCTAssertEqual(viewModel.reconnectResultText, "Still unable to connect. Try the steps below.")
    }

    func testAReconnectThatLeavesThePumpConnectedSaysSo() {
        manager.state.isConnected = true
        let viewModel = ViewModel(pumpManager: manager)

        viewModel.attemptReconnect()
        drainMainQueue()

        XCTAssertFalse(viewModel.isAttemptingReconnect)
        XCTAssertEqual(viewModel.reconnectResultText, "Connected")
    }

    func testASecondTapWhileAReconnectIsInFlightIsIgnored() {
        bluetooth.connectError = PumpCommError.pumpNotConnected
        let viewModel = ViewModel(pumpManager: manager)

        viewModel.attemptReconnect()
        viewModel.attemptReconnect()
        drainMainQueue()

        XCTAssertEqual(bluetooth.ensureConnectedCount, 1)
    }

    func testANewAttemptClearsTheLastOutcomeUntilItFinishes() {
        bluetooth.connectError = PumpCommError.pumpNotConnected
        let viewModel = ViewModel(pumpManager: manager)
        viewModel.attemptReconnect()
        drainMainQueue()
        XCTAssertNotNil(viewModel.reconnectResultText)

        viewModel.attemptReconnect()

        XCTAssertNil(viewModel.reconnectResultText)
        drainMainQueue()
    }

    // MARK: - Helpers

    /// A status update takes two hops: LoopKit's to the observer's queue, then the view model's own.
    private func drainMainQueue(hops: Int = 1) {
        for _ in 0 ..< hops {
            let drained = expectation(description: "main queue drained")
            DispatchQueue.main.async { drained.fulfill() }
            wait(for: [drained], timeout: 5.0)
        }
    }
}
