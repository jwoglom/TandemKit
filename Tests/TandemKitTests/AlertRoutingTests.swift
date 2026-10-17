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

    private func relaunch() {
        attach(state: TandemPumpManagerState(rawValue: manager.state.rawValue))
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

    /// State as a build before the identifier change saved it.
    private func legacyState(issued: Set<String>, clockSkewAlertIssued: Bool) -> TandemPumpManagerState {
        var raw = TandemPumpManagerState(rawValue: [:]).rawValue
        raw["issuedAlertIdentifiers"] = Array(issued)
        raw["pumpClockSkewAlertIssued"] = clockSkewAlertIssued
        raw.removeValue(forKey: "alertsIssuedUnderLegacyIdentifier")
        return TandemPumpManagerState(rawValue: raw)
    }

    private func legacyIdentifier(_ alertIdentifier: String) -> Alert.Identifier {
        Alert.Identifier(managerIdentifier: TandemPumpManager.legacyAlertManagerIdentifier, alertIdentifier: alertIdentifier)
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
        let alert = try XCTUnwrap(delegate.issuedAlerts.first)

        var result: Error??
        XCTAssertTrue(delegate.acknowledgeAlert(alert.identifier) { result = $0 }, "the host found no responder for \(alert.identifier)")
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
        return try XCTUnwrap(delegate.issuedAlerts.first)
    }

    private func acknowledge(_ alert: Alert) -> Error? {
        var result: Error?
        XCTAssertTrue(delegate.acknowledgeAlert(alert.identifier) { result = $0 }, "the host found no responder for \(alert.identifier)")
        delegateQueue.sync {}
        delegateQueue.sync {}
        return result
    }

    func testARefusedDismissalIssuesTheAlertAgainWhileThePumpStillRaisesIt() throws {
        attach()
        let alert = try issueLowInsulinAlert()
        bluetooth.stub(DismissNotificationRequest.self, with: DismissNotificationResponse(status: 1))

        XCTAssertNotNil(acknowledge(alert))

        XCTAssertEqual(delegate.issuedAlerts.map(\.identifier), [alert.identifier, alert.identifier])
        XCTAssertEqual(manager.state.issuedAlertIdentifiers, [alert.identifier.alertIdentifier])
    }

    func testAnAcknowledgementThatCannotReachThePumpIssuesTheAlertAgain() throws {
        attach()
        let alert = try issueLowInsulinAlert()
        bluetooth.connectError = PumpCommError.pumpNotConnected

        XCTAssertNotNil(acknowledge(alert))

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

        XCTAssertEqual(delegate.issuedAlerts.map(\.identifier), [alert.identifier])
        XCTAssertEqual(delegate.retractedAlerts, [alert.identifier])
    }

    func testAlertsIssuedUnderTheLegacyIdentifierAreRetractedOnceAtAttach() {
        attach(state: legacyState(issued: ["alarm.occlusion.2", "alert.lowInsulin.0"], clockSkewAlertIssued: true))

        XCTAssertEqual(delegate.retractedAlerts, [
            legacyIdentifier("alarm.occlusion.2"),
            legacyIdentifier("alert.lowInsulin.0"),
            legacyIdentifier(TandemPumpManager.pumpClockSkewAlertIdentifier),
        ])
        XCTAssertEqual(delegate.issuedAlerts.count, 0)
        XCTAssertEqual(manager.state.issuedAlertIdentifiers, [])
        XCTAssertFalse(manager.state.pumpClockSkewAlertIssued)
        XCTAssertFalse(manager.state.alertsIssuedUnderLegacyIdentifier)

        relaunch()

        XCTAssertEqual(delegate.retractedAlerts, [])
    }

    func testAnAlertStillStandingAfterTheMigrationIsIssuedAgainUnderThePluginIdentifier() {
        attach(state: legacyState(issued: ["alarm.occlusion.2"], clockSkewAlertIssued: false))
        stubAlerts([])
        stubAlarms([.OCCLUSION_ALARM])

        fetchNotifications()

        XCTAssertEqual(delegate.issuedAlerts.map(\.identifier), [TandemPumpManager.alertIdentifier("alarm.occlusion.2")])
        XCTAssertEqual(manager.state.issuedAlertIdentifiers, ["alarm.occlusion.2"])
    }

    func testTheClockSkewAlertIsIssuedAgainWhileThePumpClockIsStillSkewed() {
        attach(state: legacyState(issued: [], clockSkewAlertIssued: true))
        skewPumpClock(minutes: 11)

        manager.reconcilePumpClockSkewAlert()
        delegateQueue.sync {}

        XCTAssertEqual(delegate.retractedAlerts, [legacyIdentifier(TandemPumpManager.pumpClockSkewAlertIdentifier)])
        XCTAssertEqual(
            delegate.issuedAlerts.map(\.identifier),
            [TandemPumpManager.alertIdentifier(TandemPumpManager.pumpClockSkewAlertIdentifier)]
        )
    }

    func testStateWithNoAlertsHasNothingToMigrate() {
        XCTAssertFalse(legacyState(issued: [], clockSkewAlertIssued: false).alertsIssuedUnderLegacyIdentifier)
        XCTAssertFalse(TandemPumpManagerState(rawValue: [:]).alertsIssuedUnderLegacyIdentifier)

        attach()

        XCTAssertEqual(delegate.retractedAlerts, [])
    }
}
