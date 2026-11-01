import LoopKit
@testable import TandemKit
import XCTest

/// Loop and Trio route an alert's acknowledgement by its `managerIdentifier` to the responder they
/// registered under the pump manager's `pluginIdentifier` (#592).
@available(macOS 13.0, iOS 14.0, *) final class AlertRoutingTests: XCTestCase {
    private static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let lowInsulin = AlertStatusResponse.AlertResponseType.LOW_INSULIN_ALERT

    private var bluetooth: StubPumpBluetooth!
    private var clock: ManualClock!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        clock = ManualClock(Self.t0)
        delegateQueue = DispatchQueue(label: "alert-routing-test")
    }

    override func tearDown() {
        manager = nil
        delegate = nil
        bluetooth = nil
        delegateQueue = nil
        clock = nil
        super.tearDown()
    }

    private func attach(state: TandemPumpManagerState = TandemPumpManagerState(rawValue: [:])) {
        manager = TandemPumpManager(state: state, bluetooth: bluetooth, clock: clock)
        delegate = MockPumpManagerDelegate()
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegate.addAlertResponder(manager)
        delegateQueue.sync {}
    }

    private func stubAlerts(_ alerts: [AlertStatusResponse.AlertResponseType]) {
        let mask = alerts.reduce(UInt64(0)) { $0 | (UInt64(1) << UInt64($1.rawValue)) }
        bluetooth.stub(AlertStatusRequest.self, with: AlertStatusResponse(intMap: mask))
    }

    private func stubAlarms(_ alarms: [AlarmStatusResponse.AlarmResponseType]) {
        let mask = alarms.reduce(UInt64(0)) { $0 | (UInt64(1) << UInt64($1.rawValue)) }
        bluetooth.stub(AlarmStatusRequest.self, with: AlarmStatusResponse(intMap: mask))
    }

    private func fetchNotifications() {
        manager.fetchNotifications()
        delegateQueue.sync {}
    }

    private func skewPumpClock(minutes: Double) {
        manager.state.lastPumpTimeCheckDate = manager.now
        manager.state.currentPumpTime = manager.now.addingTimeInterval(.minutes(minutes))
    }

    func testEveryIssuedAndRetractedAlertCarriesThePluginIdentifier() {
        attach()
        stubAlerts([Self.lowInsulin])
        stubAlarms([.OCCLUSION_ALARM])
        fetchNotifications()
        skewPumpClock(minutes: 11)
        manager.reconcilePumpClockSkewAlert()

        stubAlerts([])
        stubAlarms([])
        fetchNotifications()
        skewPumpClock(minutes: 0)
        manager.reconcilePumpClockSkewAlert()
        delegateQueue.sync {}
        delegate.waitForAlerts { delegate.issuedAlerts.count == 3 && delegate.retractedAlerts.count == 3 }

        XCTAssertEqual(delegate.issuedAlerts.count, 3, "\(delegate.issuedAlerts)")
        XCTAssertEqual(delegate.retractedAlerts.count, 3, "\(delegate.retractedAlerts)")
        XCTAssertEqual(
            Set(delegate.issuedAlerts.map(\.identifier.managerIdentifier) + delegate.retractedAlerts.map(\.managerIdentifier)),
            [TandemPumpManager.pluginIdentifier]
        )
    }

    func testAHostAcknowledgementDismissesTheAlertOnThePump() throws {
        attach()
        var dismissed = false
        bluetooth.stub(AlertStatusRequest.self) { _ in
            AlertStatusResponse(intMap: dismissed ? 0 : UInt64(1) << UInt64(Self.lowInsulin.rawValue))
        }
        bluetooth.stub(DismissNotificationRequest.self) { _ in
            dismissed = true
            return DismissNotificationResponse(status: 0)
        }
        stubAlarms([])
        fetchNotifications()
        delegate.waitForAlerts { !delegate.issuedAlerts.isEmpty }
        let alert = try XCTUnwrap(delegate.issuedAlerts.first)

        var result: Error??
        XCTAssertTrue(delegate.acknowledgeAlert(alert.identifier) { result = $0 }, "the host found no responder for \(alert.identifier)")
        delegate.waitForAlerts { result != nil && !delegate.retractedAlerts.isEmpty }
        delegateQueue.sync {}

        let dismissals = bluetooth.sent(DismissNotificationRequest.self)
        XCTAssertEqual(dismissals.map(\.notificationType), [.alert])
        XCTAssertEqual(dismissals.map(\.notificationId), [UInt32(Self.lowInsulin.rawValue)])
        XCTAssertNotNil(result, "the acknowledgement completed")
        XCTAssertNil(result ?? nil)
        XCTAssertEqual(delegate.retractedAlerts, [alert.identifier])
        XCTAssertEqual(manager.state.issuedAlertIdentifiers, [])
    }

    private func issueLowInsulinAlert() throws -> Alert {
        stubAlerts([Self.lowInsulin])
        stubAlarms([])
        fetchNotifications()
        delegate.waitForAlerts { !delegate.issuedAlerts.isEmpty }
        return try XCTUnwrap(delegate.issuedAlerts.first)
    }

    private func acknowledge(_ alert: Alert) -> Error? {
        var result: Error??
        XCTAssertTrue(delegate.acknowledgeAlert(alert.identifier) { result = $0 }, "the host found no responder for \(alert.identifier)")
        delegate.waitForAlerts { result != nil }
        delegateQueue.sync {}
        delegateQueue.sync {}
        return result ?? nil
    }

    func testARefusedDismissalIssuesTheAlertAgainWhileThePumpStillRaisesIt() throws {
        attach()
        let alert = try issueLowInsulinAlert()
        bluetooth.stub(DismissNotificationRequest.self, with: DismissNotificationResponse(status: 1))

        XCTAssertNotNil(acknowledge(alert))
        delegate.waitForAlerts { delegate.issuedAlerts.count == 2 }

        XCTAssertEqual(delegate.issuedAlerts.map(\.identifier), [alert.identifier, alert.identifier])
        XCTAssertEqual(manager.state.issuedAlertIdentifiers, [alert.identifier.alertIdentifier])
    }

    func testAnAcknowledgementThatCannotReachThePumpIssuesTheAlertAgain() throws {
        attach()
        let alert = try issueLowInsulinAlert()
        bluetooth.connectError = PumpCommError.pumpNotConnected

        XCTAssertNotNil(acknowledge(alert))
        delegate.waitForAlerts { delegate.issuedAlerts.count == 2 }

        XCTAssertEqual(delegate.issuedAlerts.map(\.identifier), [alert.identifier, alert.identifier])
        XCTAssertFalse(bluetooth.didSend(DismissNotificationRequest.self))
    }

    func testARefusedDismissalOfAnAlertThePumpAlreadyClearedIssuesNothing() throws {
        attach()
        let alert = try issueLowInsulinAlert()
        bluetooth.stub(DismissNotificationRequest.self) { _ in
            self.stubAlerts([])
            return DismissNotificationResponse(status: 1)
        }

        XCTAssertNil(acknowledge(alert))
        delegate.waitForAlerts { !delegate.retractedAlerts.isEmpty }

        XCTAssertEqual(delegate.issuedAlerts.map(\.identifier), [alert.identifier])
        XCTAssertEqual(delegate.retractedAlerts, [alert.identifier])
    }
}
