import LoopKit
@testable import TandemKit
import XCTest

/// `enactTempBasal` while a bolus the driver started has not been seen to end (#347).
@available(macOS 13.0, iOS 14.0, *) final class TempBasalWhileABolusRunsTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var clock: ManualClock!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    /// What the stub pump runs; nil for its profile.
    private var runningPercent: Int?

    private static let bolusId = 4200
    private static let units = 2.0

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        clock = ManualClock(Date(timeIntervalSinceReferenceDate: 700_000_000))
        var state = TandemPumpManagerState(basalRateSchedule: BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!)
        state.hasSyncedBasalRateSchedule = true
        start(state: state)

        bluetooth.stub(BolusPermissionRequest.self, with: BolusPermissionResponse(status: 0, bolusId: Self.bolusId, nackReasonId: 0))
        bluetooth.stub(InitiateBolusRequest.self, with: InitiateBolusResponse(status: 0, bolusId: Self.bolusId, statusTypeId: 0))
        bluetooth.stub(CurrentBasalStatusRequest.self) { [unowned self] _ in
            CurrentBasalStatusResponse(
                profileBasalRate: 1000,
                currentBasalRate: UInt32(10 * (self.runningPercent ?? 100)),
                basalModifiedBitmask: self.runningPercent == nil ? 0 : 0x02
            )
        }
        bluetooth.stub(SetTempRateRequest.self) { [unowned self] request in
            self.runningPercent = (request as? SetTempRateRequest)?.percent
            return SetTempRateResponse(status: 0, tempRateId: 9)
        }
    }

    override func tearDown() {
        delegate = nil
        manager = nil
        clock = nil
        bluetooth = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func start(state: TandemPumpManagerState) {
        manager = TandemPumpManager(state: state, bluetooth: bluetooth, clock: clock)
        delegate = MockPumpManagerDelegate()
        manager.pumpManagerDelegate = delegate
        manager.waitForDelegateCalls()
    }

    private func relaunch() {
        start(state: TandemPumpManagerState(rawValue: manager.state.rawValue))
    }

    private func enactBolus() -> PumpManagerError? {
        let finished = expectation(description: "enactBolus")
        var result: PumpManagerError?
        manager.enactBolus(decisionId: nil, units: Self.units, activationType: .manualNoRecommendation) {
            result = $0
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5.0)
        manager.waitForDelegateCalls()
        return result
    }

    private func enactTempBasal(unitsPerHour: Double = 1.5) -> PumpManagerError? {
        let finished = expectation(description: "enactTempBasal")
        var result: PumpManagerError?
        manager.enactTempBasal(decisionId: nil, unitsPerHour: unitsPerHour, for: .minutes(30)) {
            result = $0
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5.0)
        manager.waitForDelegateCalls()
        return result
    }

    private func validationError(_ error: PumpManagerError?) -> TandemPumpManagerValidationError? {
        guard case let .deviceState(underlying?)? = error else { return nil }
        return underlying as? TandemPumpManagerValidationError
    }

    private func stubCurrentBolus(statusId: Int, bolusId: Int) {
        bluetooth.stub(CurrentBolusStatusRequest.self, with: CurrentBolusStatusResponse(
            statusId: statusId,
            bolusId: bolusId,
            timestamp: 0,
            requestedVolume: UInt32(Self.units * 1000),
            bolusSourceId: 0,
            bolusTypeBitmask: 0
        ))
    }

    private func stubLastBolus(deliveredMilliunits: UInt32) {
        bluetooth.stub(LastBolusStatusRequest.self, with: LastBolusStatusResponse(
            status: 0,
            bolusId: Self.bolusId,
            timestamp: 0,
            deliveredVolume: deliveredMilliunits,
            bolusStatusId: 0,
            bolusSourceId: 0,
            bolusTypeBitmask: 0,
            extendedBolusDuration: 0
        ))
    }

    /// The progress estimate runs from the first delivering status, so it is taken before the clock moves.
    private func seeTheBolusDelivering() {
        stubCurrentBolus(statusId: 1, bolusId: Self.bolusId)
        manager.fetchBolusStatus(fromSync: false)
        manager.waitForDelegateCalls()
    }

    private var estimatedDuration: TimeInterval {
        manager.estimatedDuration(toBolus: Self.units)
    }

    private func estimateHasRunOut() -> Bool {
        manager.bolusProgressReport?.notify()
        return manager.bolusProgressReport?.isUnfinalized() == false
    }

    // MARK: - Tests

    func testATempBasalIsRefusedWithoutConnectingWhileABolusDelivers() {
        XCTAssertNil(enactBolus())
        seeTheBolusDelivering()
        bluetooth.resetRecordedTraffic()

        XCTAssertEqual(validationError(enactTempBasal()), .bolusIsRunning)

        XCTAssertEqual(bluetooth.ensureConnectedCount, 0)
        XCTAssertTrue(bluetooth.sentMessages.isEmpty, "\(bluetooth.sentMessages)")
    }

    func testOnceTheEstimateRunsOutATempBasalIsStillRefusedWithoutConnectingInsideTheGrace() {
        XCTAssertNil(enactBolus())
        seeTheBolusDelivering()
        clock.advance(by: estimatedDuration + 5)
        XCTAssertTrue(estimateHasRunOut())
        XCTAssertTrue(manager.shouldDeferBolusSync())
        bluetooth.resetRecordedTraffic()

        XCTAssertEqual(validationError(enactTempBasal()), .bolusIsRunning)

        XCTAssertEqual(bluetooth.ensureConnectedCount, 0)
        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
    }

    func testPastTheEstimateATempBasalIsRefusedWhileThePumpStillDeliversTheBolus() {
        XCTAssertNil(enactBolus())
        seeTheBolusDelivering()
        clock.advance(by: estimatedDuration + .minutes(2))
        XCTAssertTrue(estimateHasRunOut())
        let batchesBefore = delegate.pumpEventBatches.count
        bluetooth.resetRecordedTraffic()

        XCTAssertEqual(validationError(enactTempBasal()), .bolusIsRunning)

        XCTAssertTrue(bluetooth.didSend(CurrentBolusStatusRequest.self))
        XCTAssertFalse(bluetooth.didSend(StopTempRateRequest.self))
        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
        XCTAssertEqual(manager.state.bolusDose?.bolusId, Self.bolusId)
        XCTAssertNil(runningPercent)
        XCTAssertEqual(delegate.pumpEventBatches.count, batchesBefore, "the host keeps the bolus as it holds it")
    }

    func testPastTheEstimateATempBasalIsRefusedWhenThePumpDoesNotSayWhetherTheBolusFinished() {
        XCTAssertNil(enactBolus())
        seeTheBolusDelivering()
        clock.advance(by: estimatedDuration + .minutes(2))
        bluetooth.stub(CurrentBolusStatusRequest.self) { _ in nil }
        bluetooth.resetRecordedTraffic()

        XCTAssertEqual(validationError(enactTempBasal()), .bolusIsRunning)

        XCTAssertTrue(bluetooth.didSend(CurrentBolusStatusRequest.self))
        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
    }

    func testPastTheEstimateATempBasalGoesOutOnceThePumpSaysTheBolusFinished() throws {
        XCTAssertNil(enactBolus())
        seeTheBolusDelivering()
        clock.advance(by: estimatedDuration + .minutes(2))
        stubCurrentBolus(statusId: 0, bolusId: 0)
        stubLastBolus(deliveredMilliunits: 2000)
        let batchesBefore = delegate.pumpEventBatches.count
        bluetooth.resetRecordedTraffic()

        XCTAssertNil(enactTempBasal())

        let sent = bluetooth.sentMessages
        let statusRead = try XCTUnwrap(sent.firstIndex { $0 is CurrentBolusStatusRequest }, "\(sent)")
        let setTemp = try XCTUnwrap(sent.firstIndex { $0 is SetTempRateRequest }, "\(sent)")
        XCTAssertLessThan(statusRead, setTemp)
        XCTAssertNil(manager.state.bolusDose)
        XCTAssertEqual(manager.state.basalDose.type, .tempBasal)
        let events = delegate.pumpEventBatches.dropFirst(batchesBefore).flatMap(\.events)
        let finalized = try XCTUnwrap(events.firstIndex { $0.dose?.type == .bolus && $0.dose?.isMutable == false }, "\(events)")
        let temp = try XCTUnwrap(events.firstIndex { $0.dose?.type == .tempBasal }, "\(events)")
        XCTAssertLessThan(finalized, temp, "the bolus is finalized before the temp basal goes out")
        XCTAssertEqual(events[finalized].dose?.deliveredUnits, 2.0)
    }

    func testAfterARelaunchMidBolusATempBasalIsRefusedWithoutConnecting() {
        XCTAssertNil(enactBolus())
        relaunch()
        bluetooth.resetRecordedTraffic()

        XCTAssertEqual(validationError(enactTempBasal()), .bolusIsRunning)

        XCTAssertEqual(bluetooth.ensureConnectedCount, 0)
        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
    }

    func testAfterARelaunchPastTheEstimateATempBasalIsRefusedWhileThePumpStillDeliversTheBolus() {
        XCTAssertNil(enactBolus())
        relaunch()
        clock.advance(by: estimatedDuration + .minutes(2))
        stubCurrentBolus(statusId: 1, bolusId: Self.bolusId)
        bluetooth.resetRecordedTraffic()

        XCTAssertEqual(validationError(enactTempBasal()), .bolusIsRunning)

        XCTAssertTrue(bluetooth.didSend(CurrentBolusStatusRequest.self))
        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
        XCTAssertEqual(manager.state.bolusDose?.bolusId, Self.bolusId)
    }

    func testAZeroTempIsRefusedTooWhileThePumpStillDeliversTheBolus() {
        XCTAssertNil(enactBolus())
        seeTheBolusDelivering()
        clock.advance(by: estimatedDuration + .minutes(2))
        XCTAssertTrue(estimateHasRunOut())
        bluetooth.resetRecordedTraffic()

        XCTAssertEqual(validationError(enactTempBasal(unitsPerHour: 0)), .bolusIsRunning)

        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
    }
}
