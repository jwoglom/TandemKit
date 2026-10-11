import LoopKit
@testable import TandemKit
import XCTest

/// Pump alarms and malfunctions reach the host's pump event log as `.alarm` events with an
/// `alarmType`, and their clearing as `.alarmClear` (#349). The LoopKit alerts are covered elsewhere.
@available(macOS 13.0, iOS 14.0, *) final class PumpAlarmEventTests: XCTestCase {
    private static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private var bluetooth: StubPumpBluetooth!
    private var clock: ManualClock!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        clock = ManualClock(Self.t0)
        delegateQueue = DispatchQueue(label: "pump-alarm-event-test")
        manager = makeManager(state: TandemPumpManagerState(rawValue: [:]))
    }

    override func tearDown() {
        manager = nil
        delegate = nil
        bluetooth = nil
        delegateQueue = nil
        clock = nil
        super.tearDown()
    }

    private func makeManager(state: TandemPumpManagerState) -> TandemPumpManager {
        let manager = TandemPumpManager(state: state, bluetooth: bluetooth, clock: clock)
        delegate = MockPumpManagerDelegate()
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}
        return manager
    }

    private func stubAlarms(_ alarms: [AlarmStatusResponse.AlarmResponseType]) {
        let mask = alarms.reduce(UInt64(0)) { $0 | (UInt64(1) << UInt64($1.rawValue)) }
        bluetooth.stub(AlarmStatusRequest.self, with: AlarmStatusResponse(intMap: mask))
    }

    private func fetchNotifications() -> [NewPumpEvent] {
        let before = delegate.pumpEventBatches.count
        manager.fetchNotifications()
        delegateQueue.sync {}
        return delegate.pumpEventBatches.dropFirst(before).flatMap(\.events)
    }

    func testAnOcclusionIsReportedAsAnAlarmEventWithItsType() throws {
        stubAlarms([.OCCLUSION_ALARM])

        let events = fetchNotifications()

        let alarm = try XCTUnwrap(events.first)
        XCTAssertEqual(events.count, 1, "\(events)")
        XCTAssertEqual(alarm.type, .alarm)
        XCTAssertEqual(alarm.alarmType, .occlusion)
        XCTAssertNil(alarm.dose)
        XCTAssertEqual(alarm.date, Self.t0)
        XCTAssertEqual(alarm.title, "Occlusion Alarm")
        XCTAssertEqual(delegate.pumpEventBatches.last?.replacePendingEvents, false, "a marker does not purge pending doses")
    }

    func testAStandingAlarmIsReportedOnce() {
        stubAlarms([.EMPTY_CARTRIDGE_ALARM])
        XCTAssertEqual(fetchNotifications().map(\.type), [.alarm])

        clock.advance(by: .minutes(5))

        XCTAssertEqual(fetchNotifications(), [])
    }

    func testAnAlarmThatClearsIsReportedAsAnAlarmClearAtTheReadThatFindsItGone() throws {
        stubAlarms([.OCCLUSION_ALARM])
        let alarm = try XCTUnwrap(fetchNotifications().first)
        clock.advance(by: .minutes(5))
        stubAlarms([])

        let events = fetchNotifications()

        let cleared = try XCTUnwrap(events.first)
        XCTAssertEqual(events.count, 1, "\(events)")
        XCTAssertEqual(cleared.type, .alarmClear)
        XCTAssertNil(cleared.alarmType)
        XCTAssertEqual(cleared.date, Self.t0.addingTimeInterval(.minutes(5)))
        XCTAssertNotEqual(cleared.raw, alarm.raw)
        XCTAssertEqual(manager.state.reportedPumpAlarmIdentifiers, [])
    }

    func testAnUnansweredAlarmStatusReadDoesNotClearAnAlarm() {
        stubAlarms([.OCCLUSION_ALARM])
        _ = fetchNotifications()
        bluetooth.stub(AlarmStatusRequest.self) { _ in nil }

        XCTAssertEqual(fetchNotifications(), [])
        XCTAssertEqual(manager.state.reportedPumpAlarmIdentifiers, ["alarm.occlusion.2"])
    }

    func testAnAlarmReplacedByAnotherIsClearedThenTheNewOneReported() {
        stubAlarms([.OCCLUSION_ALARM])
        _ = fetchNotifications()
        stubAlarms([.RESUME_PUMP_ALARM])

        let events = fetchNotifications()

        XCTAssertEqual(events.map(\.type), [.alarmClear, .alarm])
        XCTAssertEqual(events.last?.alarmType, .noDelivery)
    }

    func testTheTwoBitsOfOneConditionAreOneAlarm() {
        stubAlarms([.OCCLUSION_ALARM, .OCCLUSION_ALARM2])

        let events = fetchNotifications()

        XCTAssertEqual(events.map(\.alarmType), [.occlusion])
    }

    func testAlertsAreIssuedAsLoopKitAlertsButNotReportedAsAlarms() {
        bluetooth.stub(AlertStatusRequest.self, with: AlertStatusResponse(intMap: UInt64(1) << UInt64(AlertStatusResponse.AlertResponseType.LOW_INSULIN_ALERT.rawValue)))
        stubAlarms([])

        XCTAssertEqual(fetchNotifications(), [])
        XCTAssertEqual(delegate.issuedAlerts.map(\.identifier.alertIdentifier), ["alert.lowInsulin.0"])
    }

    func testAStandingAlarmIsNotReportedAgainAfterARelaunch() {
        stubAlarms([.OCCLUSION_ALARM])
        _ = fetchNotifications()

        manager = makeManager(state: TandemPumpManagerState(rawValue: manager.state.rawValue))

        XCTAssertEqual(fetchNotifications(), [])
        stubAlarms([])
        XCTAssertEqual(fetchNotifications().map(\.type), [.alarmClear], "the relaunched driver still reports its clearing")
    }

    func testAnAlarmReadWithNoDelegateIsReportedOnceOneAttaches() throws {
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth, clock: clock)
        stubAlarms([.AUTO_OFF_ALARM])
        manager.fetchNotifications()

        delegate = MockPumpManagerDelegate()
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}

        let alarm = try XCTUnwrap(delegate.pumpEventBatches.flatMap(\.events).first)
        XCTAssertEqual(alarm.alarmType, .autoOff)
        XCTAssertEqual(alarm.date, Self.t0, "dated when the pump was read, not when the host attached")
    }

    func testEachAlarmMapsOntoLoopKitsAlarmTypeOrItsSlug() {
        let expected: [(AlarmStatusResponse.AlarmResponseType, PumpAlarmType)] = [
            (.OCCLUSION_ALARM, .occlusion),
            (.OCCLUSION_ALARM2, .occlusion),
            (.EMPTY_CARTRIDGE_ALARM, .noInsulin),
            (.AUTO_OFF_ALARM, .autoOff),
            (.BATTERY_SHUTDOWN_ALARM, .noPower),
            (.RESUME_PUMP_ALARM, .noDelivery),
            (.RESUME_PUMP_ALARM2, .noDelivery),
            (.CARTRIDGE_ALARM_MOTOR_STALL, .other("cartridge")),
            (.CARTRIDGE_REMOVED_ALARM, .other("cartridgeRemoved")),
            (.TEMPERATURE_ALARM2, .other("temperature")),
            (.PUMP_RESET_ALARM, .other("pumpReset")),
            (.DEFAULT_ALARM_13, .other("DEFAULT_ALARM_13"))
        ]
        for (alarm, alarmType) in expected {
            XCTAssertEqual(alarm.pumpAlarmType, alarmType, "\(alarm)")
        }
    }

    func testAMalfunctionIsAnAlarmNamingItsFaultCode() {
        let item = NotificationItem(type: .malfunction, id: 12, name: "12-0x2071")

        let event = NewPumpEvent.pumpAlarm(item, date: Self.t0)

        XCTAssertEqual(event.type, .alarm)
        XCTAssertEqual(event.alarmType, .other("malfunction"))
        XCTAssertEqual(event.title, "Pump Malfunction 12-0x2071")
    }

    func testReportedAlarmsRoundTripThroughRawValue() {
        var state = TandemPumpManagerState(rawValue: [:])
        state.reportedPumpAlarmIdentifiers = ["alarm.occlusion.2", "malfunction.12"]

        XCTAssertEqual(TandemPumpManagerState(rawValue: state.rawValue).reportedPumpAlarmIdentifiers, ["alarm.occlusion.2", "malfunction.12"])
        XCTAssertEqual(TandemPumpManagerState(rawValue: [:]).reportedPumpAlarmIdentifiers, [])
    }
}
