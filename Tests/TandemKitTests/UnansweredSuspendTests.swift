import LoopKit
@testable import TandemKit
import XCTest

/// A `SuspendPumping` whose answer was lost or refused, after the stop of a temp it ends (#340).
@available(macOS 13.0, iOS 14.0, *) final class UnansweredSuspendTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var clock: ManualClock!
    /// What the stub pump runs; nil for its profile.
    private var runningPercent: Int?
    private var isSuspended = false

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        clock = ManualClock()
        var state = TandemPumpManagerState(basalRateSchedule: BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!)
        state.hasSyncedBasalRateSchedule = true
        state.insulinType = .novolog
        manager = TandemPumpManager(state: state, bluetooth: bluetooth)
        manager.clock = clock
        delegate = MockPumpManagerDelegate()
        manager.pumpManagerDelegate = delegate
        manager.waitForDelegateCalls()

        bluetooth.stub(CurrentBasalStatusRequest.self) { [unowned self] _ in
            if self.isSuspended {
                return CurrentBasalStatusResponse(profileBasalRate: 1000, currentBasalRate: 0, basalModifiedBitmask: 0x01)
            }
            return CurrentBasalStatusResponse(
                profileBasalRate: 1000,
                currentBasalRate: UInt32(10 * (self.runningPercent ?? 100)),
                basalModifiedBitmask: self.runningPercent == nil ? 0 : 0x02
            )
        }
        bluetooth.stub(SetTempRateRequest.self) { [unowned self] request in
            self.runningPercent = (request as? SetTempRateRequest)?.percent
            return SetTempRateResponse(status: 0, tempRateId: 8)
        }
        bluetooth.stub(StopTempRateRequest.self) { [unowned self] _ in
            self.runningPercent = nil
            return StopTempRateResponse(status: 0, tempRateId: 8)
        }
        bluetooth.stub(TempRateRequest.self) { [unowned self] _ in
            TempRateResponse(active: self.runningPercent != nil, percentage: self.runningPercent ?? 0, startTimeRaw: 0, duration: 0)
        }
    }

    override func tearDown() {
        manager = nil
        delegate = nil
        bluetooth = nil
        super.tearDown()
    }

    /// The pump suspends, or not, and the answer never comes.
    private func loseTheAnswer(applying: Bool) {
        bluetooth.stub(SuspendPumpingRequest.self) { [unowned self] _ in
            if applying {
                self.runningPercent = nil
                self.isSuspended = true
            }
            return nil
        }
    }

    private func suspend() -> Error? {
        let done = expectation(description: "suspend completion")
        var error: Error?
        manager.suspendDelivery {
            error = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        manager.waitForDelegateCalls()
        return error
    }

    private func enactTempBasal(unitsPerHour: Double) -> PumpManagerError? {
        let done = expectation(description: "temp basal completion")
        var error: PumpManagerError?
        manager.enactTempBasal(decisionId: nil, unitsPerHour: unitsPerHour, for: .minutes(30)) {
            error = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        manager.waitForDelegateCalls()
        return error
    }

    private var doses: [DoseEntry] {
        delegate.pumpEventBatches.flatMap(\.events).compactMap(\.dose)
    }

    func testASuspendThePumpAppliedDespiteALostAnswerIsReported() {
        loseTheAnswer(applying: true)

        XCTAssertNil(suspend())

        XCTAssertEqual(manager.state.basalDose.type, .suspend)
        XCTAssertEqual(doses.filter { $0.type == .suspend }.map(\.startDate), [clock.now])
    }

    func testTheTempTheStopEndedFinishesAtTheReportedSuspend() {
        XCTAssertNil(enactTempBasal(unitsPerHour: 1.5))
        clock.advance(by: .minutes(5))
        loseTheAnswer(applying: true)

        XCTAssertNil(suspend())

        let temp = doses.last { $0.type == .tempBasal }
        XCTAssertEqual(temp?.isMutable, false)
        XCTAssertEqual(temp?.endDate, clock.now)
        XCTAssertEqual(doses.filter { $0.type == .suspend }.map(\.startDate), [clock.now])
    }

    func testASuspendThePumpNeverAppliedReportsNoSuspend() {
        loseTheAnswer(applying: false)

        XCTAssertNotNil(suspend())

        XCTAssertEqual(bluetooth.sent(CurrentBasalStatusRequest.self).count, 1)
        XCTAssertNotEqual(manager.state.basalDose.type, .suspend)
        XCTAssertFalse(doses.contains { $0.type == .suspend })
    }

    func testARefusedSuspendFinishesTheTempItsStopEnded() {
        XCTAssertNil(enactTempBasal(unitsPerHour: 1.5))
        clock.advance(by: .minutes(5))
        bluetooth.stub(SuspendPumpingRequest.self, with: SuspendPumpingResponse(status: 1))

        XCTAssertNotNil(suspend())

        XCTAssertEqual(doses.last { $0.type == .tempBasal }?.isMutable, false)
        XCTAssertEqual(manager.state.basalDose.type, .basal)
        XCTAssertFalse(doses.contains { $0.type == .suspend })
    }

    func testARefusalFromAPumpAlreadySuspendedSucceeds() {
        isSuspended = true
        bluetooth.stub(SuspendPumpingRequest.self, with: SuspendPumpingResponse(status: 1))

        XCTAssertNil(suspend())

        XCTAssertEqual(manager.state.basalDose.type, .suspend)
        XCTAssertEqual(doses.filter { $0.type == .suspend }.count, 1)
    }

    func testWithoutAReadingNothingIsReported() {
        loseTheAnswer(applying: true)
        bluetooth.stub(CurrentBasalStatusRequest.self) { _ in nil }

        XCTAssertNotNil(suspend())

        XCTAssertNotEqual(manager.state.basalDose.type, .suspend)
        XCTAssertTrue(doses.isEmpty)
    }
}
