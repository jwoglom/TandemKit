import CoreBluetooth
import Foundation
import LoopKit
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

    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
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

    // MARK: - What the pump was last seen delivering

    func testADroppedLinkIsDescribedByWhatThePumpWasLastSeenDelivering() {
        let lastContact = Date().addingTimeInterval(-.minutes(5))
        manager.state.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 0.8)])!
        manager.state.hasSyncedBasalRateSchedule = true
        manager.state.lastReconciliation = lastContact
        manager.state.basalDose = UnfinalizedDose(basalRate: 0.8, insulinType: .novolog, startDate: lastContact)

        let viewModel = ViewModel(pumpManager: manager)

        XCTAssertEqual(viewModel.connectionIssue, .pumpUnreachable)
        XCTAssertEqual(
            viewModel.lastKnownBasalDelivery,
            LastKnownBasalDelivery(lastContact: lastContact, delivery: .profile(unitsPerHour: 0.8))
        )
        XCTAssertEqual(
            PumpConnectionIssue.pumpUnreachable.detail(
                appName: "Trio",
                lastKnownDelivery: viewModel.lastKnownBasalDelivery,
                now: lastContact.addingTimeInterval(.minutes(5))
            ),
            "Trio has not connected to your pump since \(time(lastContact)) (5 minutes ago). At that time, the pump was delivering basal at the profile basal rate of 0.80 U/hr and will continue to deliver basal as programmed until reconnected."
        )
    }

    func testAPumpThatHasNeverSyncedKeepsTheGeneralDisconnectedDetail() {
        let viewModel = ViewModel(pumpManager: manager)

        XCTAssertNil(viewModel.lastKnownBasalDelivery)
        XCTAssertTrue(
            PumpConnectionIssue.pumpUnreachable.detail(appName: "Trio", lastKnownDelivery: nil)
                .hasPrefix("Trio is not connected to your pump")
        )
    }

    // MARK: - When the pump was last connected to

    private static let allIssues: [PumpConnectionIssue] = [
        .bluetoothOff, .bluetoothUnauthorized, .bluetoothUnavailable, .pumpUnreachable, .handshakeFailing, .noRecentSync
    ]
    private static let lastSync = Date(timeIntervalSinceReferenceDate: 700_000_000)

    func testEveryNoticeSaysSinceWhenThePumpWasLastConnectedTo() {
        let now = Self.lastSync.addingTimeInterval(.minutes(12))

        for issue in Self.allIssues {
            let detail = issue.detail(appName: "Trio", lastSync: Self.lastSync, now: now)

            XCTAssertTrue(detail.contains("since \(time(Self.lastSync)) (12 minutes ago)"), "\(issue): \(detail)")
        }
    }

    func testAHandshakeThePumpKeepsEndingSaysSinceWhenThePumpWasLastConnectedTo() {
        let detail = PumpConnectionIssue.handshakeFailing.detail(
            appName: "Trio",
            lastSync: Self.lastSync,
            now: Self.lastSync.addingTimeInterval(.minutes(12))
        )

        XCTAssertTrue(
            detail.hasPrefix("Your pump is rejecting connections from this device since \(time(Self.lastSync)) (12 minutes ago). This may be caused by"),
            detail
        )
        XCTAssertTrue(detail.contains("re-pair to resume Trio controlling insulin delivery."), detail)
    }

    func testADroppedLinkWithNothingKnownOfTheDeliverySaysSinceWhenThePumpWasLastConnectedTo() {
        let detail = PumpConnectionIssue.pumpUnreachable.detail(
            appName: "Trio",
            lastKnownDelivery: nil,
            lastSync: Self.lastSync,
            now: Self.lastSync.addingTimeInterval(.minutes(12))
        )

        XCTAssertTrue(
            detail.hasPrefix("Trio has not connected to your pump since \(time(Self.lastSync)) (12 minutes ago), so it cannot read from it"),
            detail
        )
    }

    func testAPumpThatHasNeverConnectedGivesNoTimeInAnyNotice() {
        for issue in Self.allIssues {
            let detail = issue.detail(appName: "Trio", lastSync: nil, now: Self.lastSync)

            XCTAssertFalse(detail.contains(" ago)"), "\(issue): \(detail)")
        }
        XCTAssertTrue(
            PumpConnectionIssue.handshakeFailing.detail(appName: "Trio")
                .hasPrefix("Your pump is rejecting connections from this device. This may be caused by")
        )
    }

    func testALastConnectionMoreThanHalfADayAgoCarriesItsDate() {
        let now = Self.lastSync.addingTimeInterval(.hours(20))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        let detail = PumpConnectionIssue.handshakeFailing.detail(appName: "Trio", lastSync: Self.lastSync, now: now)

        XCTAssertTrue(
            detail.hasPrefix("Your pump is rejecting connections from this device since \(formatter.string(from: Self.lastSync)) (20 hours ago)."),
            detail
        )
    }

    func testAStatusUpdateRefreshesWhatThePumpWasLastSeenDelivering() {
        let viewModel = ViewModel(pumpManager: manager)
        XCTAssertNil(viewModel.lastKnownBasalDelivery)

        manager.state.lastReconciliation = Date()
        manager.state.basalDose = UnfinalizedDose(suspendStartTime: Date())
        manager.notifyDelegateStateUpdated()
        drainMainQueue(hops: 2)

        XCTAssertEqual(viewModel.lastKnownBasalDelivery?.delivery, .suspended)
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
