import LoopKit
@testable import TandemKit
import XCTest

/// A `SetTempRate` the pump applied but whose answer was lost (#340).
@available(macOS 13.0, iOS 14.0, *) final class UnansweredTempBasalTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!
    private var clock: ManualClock!
    /// What the stub pump runs; nil for its profile.
    private var runningPercent: Int?

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
        delegateQueue = DispatchQueue(label: "unanswered-temp-basal-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}

        bluetooth.stub(CurrentBasalStatusRequest.self) { [unowned self] _ in
            CurrentBasalStatusResponse(
                profileBasalRate: 1000,
                currentBasalRate: UInt32(10 * (self.runningPercent ?? 100)),
                basalModifiedBitmask: self.runningPercent == nil ? 0 : 0x02
            )
        }
        bluetooth.stub(StopTempRateRequest.self) { [unowned self] _ in
            self.runningPercent = nil
            return StopTempRateResponse(status: 0, tempRateId: 7)
        }
        bluetooth.stub(TempRateRequest.self) { [unowned self] _ in
            TempRateResponse(active: self.runningPercent != nil, percentage: self.runningPercent ?? 0, startTimeRaw: 0, duration: 0)
        }
    }

    override func tearDown() {
        manager = nil
        delegate = nil
        delegateQueue = nil
        bluetooth = nil
        super.tearDown()
    }

    /// The pump applies the set, or not, and the answer never comes.
    private func loseTheAnswer(applying: Bool) {
        bluetooth.stub(SetTempRateRequest.self) { [unowned self] request in
            if applying {
                self.runningPercent = (request as? SetTempRateRequest)?.percent
            }
            return nil
        }
    }

    private func enactTempBasal(unitsPerHour: Double) -> PumpManagerError? {
        let done = expectation(description: "temp basal completion")
        var error: PumpManagerError?
        manager.enactTempBasal(unitsPerHour: unitsPerHour, for: .minutes(30)) {
            error = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        delegateQueue.sync {}
        return error
    }

    private var tempBasals: [DoseEntry] {
        delegate.pumpEventBatches.flatMap(\.events).compactMap(\.dose).filter { $0.type == .tempBasal }
    }

    func testATempThePumpRunsDespiteALostAnswerIsReported() {
        loseTheAnswer(applying: true)

        let error = enactTempBasal(unitsPerHour: 1.5)

        guard case .communication? = error else {
            return XCTFail("a lost answer is still a communication error, got \(String(describing: error))")
        }
        XCTAssertEqual(manager.state.basalDose.type, .tempBasal)
        XCTAssertEqual(manager.state.basalDose.value, 1.5)
        XCTAssertEqual(manager.state.basalDose.tempPercent, 150)
        XCTAssertEqual(tempBasals.last?.unitsPerHour, 1.5)
        XCTAssertEqual(tempBasals.last?.isMutable, true)
    }

    func testTheTempItReplacedEndsWhenTheLostOneStarts() {
        bluetooth.stub(SetTempRateRequest.self) { [unowned self] request in
            self.runningPercent = (request as? SetTempRateRequest)?.percent
            return SetTempRateResponse(status: 0, tempRateId: 8)
        }
        XCTAssertNil(enactTempBasal(unitsPerHour: 1.2))
        clock.advance(by: .minutes(5))
        loseTheAnswer(applying: true)

        _ = enactTempBasal(unitsPerHour: 1.5)

        let replaced = tempBasals.last { $0.unitsPerHour == 1.2 && !$0.isMutable }
        XCTAssertEqual(replaced?.endDate, clock.now, "finished where the pump took up the new one")
        XCTAssertEqual(manager.state.basalDose.value, 1.5)
        XCTAssertEqual(manager.state.basalDose.startDate, clock.now)
    }

    func testASetThePumpNeverAppliedReportsNoTemp() {
        loseTheAnswer(applying: false)

        _ = enactTempBasal(unitsPerHour: 1.5)

        XCTAssertNotEqual(manager.state.basalDose.type, .tempBasal)
        XCTAssertTrue(tempBasals.isEmpty)
    }
}
