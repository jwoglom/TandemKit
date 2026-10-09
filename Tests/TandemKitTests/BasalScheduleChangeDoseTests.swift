import LoopKit
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class BasalScheduleChangeDoseTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var sixAM: Date!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        sixAM = Calendar.current.startOfDay(for: Date(timeIntervalSinceReferenceDate: 700_000_000))
            .addingTimeInterval(.hours(6))
        manager.clock = ManualClock(sixAM)
        bluetooth.stub(StopTempRateRequest.self, with: StopTempRateResponse(status: 0, tempRateId: 1))
    }

    override func tearDown() {
        manager = nil
        bluetooth = nil
        sixAM = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func start(schedule items: [(TimeInterval, Double)], pumpReports basalType: Int) {
        manager.state.basalRateSchedule = BasalRateSchedule(
            dailyItems: items.map { RepeatingScheduleValue(startTime: $0.0, value: $0.1) }
        )!
        StubIDPPump(items.map { .init(startTime: Int($0.0 / 60), basalRate: Int(($0.1 * 1000).rounded())) })
            .install(on: bluetooth)
        bluetooth.stub(CurrentBasalStatusRequest.self, with: CurrentBasalStatusResponse(
            profileBasalRate: 750,
            currentBasalRate: 1380,
            basalModifiedBitmask: basalType
        ))
    }

    private func runningTempBasal() -> UnfinalizedDose {
        UnfinalizedDose(
            tempRate: 1.38,
            duration: .minutes(30),
            automatic: true,
            insulinType: nil,
            startDate: sixAM.addingTimeInterval(-.minutes(2))
        )
    }

    private func sync(_ items: [(TimeInterval, Double)]) -> Result<BasalRateSchedule, Error> {
        var result: Result<BasalRateSchedule, Error>!
        let expectation = expectation(description: "syncBasalRateSchedule")
        manager.syncBasalRateSchedule(items: items.map { RepeatingScheduleValue(startTime: $0.0, value: $0.1) }) {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
        return result
    }

    private let tempBasal = 0x02
    private let suspended = 0x01
    private let scheduledBasal = 0x00

    // MARK: - Tests

    func testStopsARunningTempBasalAndRecordsTheNewScheduledRate() {
        start(schedule: [(0, 0.75)], pumpReports: tempBasal)
        manager.state.basalDose = runningTempBasal()

        guard case .success = sync([(0, 0.5)]) else { return XCTFail("Expected the sync to succeed") }

        XCTAssertEqual(bluetooth.sent(StopTempRateRequest.self).count, 1)
        XCTAssertEqual(manager.state.basalDose.type, .basal)
        XCTAssertEqual(manager.state.basalDose.value, 0.5)
        XCTAssertEqual(manager.state.basalDose.startDate, sixAM)
    }

    func testRestartsTheScheduledBasalDoseAtTheNewRate() {
        start(schedule: [(0, 0.75)], pumpReports: scheduledBasal)
        manager.state.basalDose = UnfinalizedDose(basalRate: 0.75, insulinType: nil, startDate: sixAM.addingTimeInterval(-.hours(1)))

        guard case .success = sync([(0, 0.5)]) else { return XCTFail("Expected the sync to succeed") }

        XCTAssertTrue(bluetooth.sent(StopTempRateRequest.self).isEmpty)
        XCTAssertEqual(manager.state.basalDose.type, .basal)
        XCTAssertEqual(manager.state.basalDose.value, 0.5)
        XCTAssertEqual(manager.state.basalDose.startDate, sixAM)
    }

    /// After re-pairing the driver starts on a default scheduled basal dose while the pump may
    /// still be running a temp basal the previous manager set.
    func testStopsATempBasalTheDriverDidNotKnowAbout() {
        start(schedule: [(0, 0.75)], pumpReports: tempBasal)
        manager.state.basalDose = UnfinalizedDose(basalRate: 0.75, insulinType: nil, startDate: sixAM)

        guard case .success = sync([(0, 0.5)]) else { return XCTFail("Expected the sync to succeed") }

        XCTAssertEqual(bluetooth.sent(StopTempRateRequest.self).count, 1)
        XCTAssertEqual(manager.state.basalDose.value, 0.5)
    }

    func testLeavesASuspendAlone() {
        start(schedule: [(0, 0.75)], pumpReports: suspended)
        manager.state.basalDose = UnfinalizedDose(suspendStartTime: sixAM.addingTimeInterval(-.minutes(10)))

        guard case .success = sync([(0, 0.5)]) else { return XCTFail("Expected the sync to succeed") }

        XCTAssertTrue(bluetooth.sent(StopTempRateRequest.self).isEmpty)
        XCTAssertEqual(manager.state.basalDose.type, .suspend)
    }

    func testLeavesTheTempBasalWhenOnlyAnotherSegmentChanged() {
        start(schedule: [(0, 0.75), (3600.0 * 12, 1.0)], pumpReports: tempBasal)
        manager.state.basalDose = runningTempBasal()

        guard case .success = sync([(0, 0.75), (3600.0 * 12, 0.8)]) else {
            return XCTFail("Expected the sync to succeed")
        }

        XCTAssertFalse(bluetooth.didSend(CurrentBasalStatusRequest.self))
        XCTAssertTrue(bluetooth.sent(StopTempRateRequest.self).isEmpty)
        XCTAssertEqual(manager.state.basalDose.type, .tempBasal)
    }

    /// The profile is on the pump either way, so the host must still be told the save succeeded.
    func testFailedTempStopStillReportsTheScheduleSaved() {
        start(schedule: [(0, 0.75)], pumpReports: tempBasal)
        bluetooth.stub(StopTempRateRequest.self, with: StopTempRateResponse(status: 1, tempRateId: 1))
        manager.state.basalDose = runningTempBasal()

        guard case .success = sync([(0, 0.5)]) else { return XCTFail("Expected the sync to succeed") }

        XCTAssertEqual(manager.state.basalDose.type, .tempBasal)
    }

    func testKeepsARunningZeroTemp() {
        start(schedule: [(0, 0.75)], pumpReports: tempBasal)
        bluetooth.stub(CurrentBasalStatusRequest.self, with: CurrentBasalStatusResponse(
            profileBasalRate: 750,
            currentBasalRate: 0,
            basalModifiedBitmask: tempBasal
        ))
        manager.state.basalDose = UnfinalizedDose(
            tempRate: 0,
            duration: .minutes(30),
            automatic: true,
            insulinType: nil,
            startDate: sixAM.addingTimeInterval(-.minutes(2))
        )

        guard case .success = sync([(0, 0.5)]) else { return XCTFail("Expected the sync to succeed") }

        XCTAssertTrue(bluetooth.sent(StopTempRateRequest.self).isEmpty)
        XCTAssertEqual(manager.state.basalDose.type, .tempBasal)
        XCTAssertEqual(manager.state.basalDose.value, 0)
    }

    /// The pump ran its own 0.75 profile under an app schedule of 0.5, so writing that same 0.5
    /// changes the rate in force.
    func testStopsATempBasalWhenThePumpsOwnProfileHeldAnotherRate() {
        start(schedule: [(0, 0.75)], pumpReports: tempBasal)
        manager.state.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 0.5)])!
        manager.state.basalDose = runningTempBasal()

        guard case .success = sync([(0, 0.5)]) else { return XCTFail("Expected the sync to succeed") }

        XCTAssertEqual(bluetooth.sent(StopTempRateRequest.self).count, 1)
        XCTAssertEqual(manager.state.basalDose.value, 0.5)
    }

    func testControlIQKeepsItsOwnTempBasal() {
        start(schedule: [(0, 0.75)], pumpReports: tempBasal)
        manager.state.useControlIQ = true
        manager.state.basalDose = runningTempBasal()

        guard case .success = sync([(0, 0.5)]) else { return XCTFail("Expected the sync to succeed") }

        XCTAssertTrue(bluetooth.sent(StopTempRateRequest.self).isEmpty)
    }
}
