import LoopKit
@testable import TandemKit
import XCTest

/// `enactBolus` while a bolus the driver started has not been seen to end (#504).
@available(macOS 13.0, iOS 14.0, *) final class BolusInFlightTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var clock: ManualClock!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!

    private static let firstBolusId = 4100
    private static let secondBolusId = 4101
    private static let units = 2.0

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        clock = ManualClock(Date(timeIntervalSinceReferenceDate: 700_000_000))
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth, clock: clock)
        delegate = MockPumpManagerDelegate()
        manager.pumpManagerDelegate = delegate
        manager.waitForDelegateCalls()
    }

    override func tearDown() {
        delegate = nil
        manager = nil
        clock = nil
        bluetooth = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func grantBoluses(_ bolusIds: [Int]) {
        bluetooth.enqueue(BolusPermissionRequest.self, responses: bolusIds.map {
            BolusPermissionResponse(status: 0, bolusId: $0, nackReasonId: 0)
        })
        bluetooth.stub(InitiateBolusRequest.self) { request in
            InitiateBolusResponse(status: 0, bolusId: (request as! InitiateBolusRequest).bolusID, statusTypeId: 0)
        }
    }

    private func enactBolus(_ activationType: BolusActivationType = .manualNoRecommendation) -> PumpManagerError? {
        let finished = expectation(description: "enactBolus")
        var result: PumpManagerError?
        manager.enactBolus(decisionId: nil, units: Self.units, activationType: activationType) {
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

    private func advancePastTheFirstBolus() {
        clock.advance(by: manager.estimatedDuration(toBolus: Self.units) + .minutes(2))
    }

    /// Enacts a second bolus from inside the first's command job, as a host's SMB arriving while a
    /// manual bolus is still being initiated does.
    private func enactASecondBolusDuringTheFirstsPermissionRequest() -> (first: PumpManagerError?, second: PumpManagerError?) {
        let secondFinished = expectation(description: "second enactBolus")
        var second: PumpManagerError?
        var enactedSecond = false
        bluetooth.onWrite = { message in
            guard message is BolusPermissionRequest, !enactedSecond else { return }
            enactedSecond = true
            self.manager.enactBolus(decisionId: nil, units: Self.units, activationType: .automatic) {
                second = $0
                secondFinished.fulfill()
            }
        }

        let first = enactBolus()
        wait(for: [secondFinished], timeout: 5.0)
        return (first, second)
    }

    // MARK: - Tests

    func testABolusQueuedBehindOneBeingInitiatedIsRefusedBeforeReachingThePump() {
        grantBoluses([Self.firstBolusId, Self.secondBolusId])

        let (first, second) = enactASecondBolusDuringTheFirstsPermissionRequest()

        XCTAssertNil(first)
        XCTAssertEqual(validationError(second), .bolusIsRunning, "\(String(describing: second))")
        XCTAssertEqual(bluetooth.sent(BolusPermissionRequest.self).count, 1)
        XCTAssertEqual(bluetooth.sent(InitiateBolusRequest.self).map(\.bolusID), [Self.firstBolusId])
        XCTAssertEqual(manager.state.bolusDose?.bolusId, Self.firstBolusId)
    }

    func testABolusQueuedBehindOneThePumpRefusedGoesOut() {
        bluetooth.enqueue(BolusPermissionRequest.self, responses: [
            BolusPermissionResponse(status: 1, bolusId: 0, nackReasonId: 1),
            BolusPermissionResponse(status: 0, bolusId: Self.secondBolusId, nackReasonId: 0)
        ])
        bluetooth.stub(InitiateBolusRequest.self, with: InitiateBolusResponse(status: 0, bolusId: Self.secondBolusId, statusTypeId: 0))

        let (first, second) = enactASecondBolusDuringTheFirstsPermissionRequest()

        XCTAssertNotNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(bluetooth.sent(InitiateBolusRequest.self).map(\.bolusID), [Self.secondBolusId])
    }

    func testABolusIsRefusedWithoutConnectingWhileAnotherIsDelivering() {
        grantBoluses([Self.firstBolusId, Self.secondBolusId])
        XCTAssertNil(enactBolus())
        bluetooth.resetRecordedTraffic()

        XCTAssertEqual(validationError(enactBolus(.automatic)), .bolusIsRunning)
        XCTAssertEqual(bluetooth.ensureConnectedCount, 0)
        XCTAssertEqual(manager.state.bolusDose?.bolusId, Self.firstBolusId)
    }

    func testABolusGoesOutAfterTheLastOneWasCancelled() {
        grantBoluses([Self.firstBolusId, Self.secondBolusId])
        XCTAssertNil(enactBolus())
        bluetooth.stub(CancelBolusRequest.self, with: CancelBolusResponse(statusId: 0, bolusId: Self.firstBolusId, reasonId: 0))
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        let cancelled = expectation(description: "cancelBolus")
        manager.cancelBolus { _ in cancelled.fulfill() }
        wait(for: [cancelled], timeout: 15.0)
        XCTAssertEqual(manager.status.bolusState, .noBolus)

        XCTAssertNil(enactBolus())

        XCTAssertEqual(bluetooth.sent(InitiateBolusRequest.self).map(\.bolusID), [Self.firstBolusId, Self.secondBolusId])
    }

    func testPastTheLastBolussEstimatedEndABolusGoesOutOnceThePumpSaysItFinished() {
        grantBoluses([Self.firstBolusId, Self.secondBolusId])
        XCTAssertNil(enactBolus())
        advancePastTheFirstBolus()
        stubCurrentBolus(statusId: 0, bolusId: 0)
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        bluetooth.resetRecordedTraffic()

        XCTAssertNil(enactBolus())

        XCTAssertTrue(bluetooth.sentMessages.first is CurrentBolusStatusRequest, "\(bluetooth.sentMessages)")
        XCTAssertEqual(bluetooth.sent(InitiateBolusRequest.self).map(\.bolusID), [Self.secondBolusId])
        XCTAssertEqual(manager.state.bolusDose?.bolusId, Self.secondBolusId)
        XCTAssertEqual(manager.state.pendingBolusFinalization?.bolusId, Self.firstBolusId)
    }

    func testPastTheLastBolussEstimatedEndABolusIsRefusedWhileThePumpStillDeliversIt() {
        grantBoluses([Self.firstBolusId, Self.secondBolusId])
        XCTAssertNil(enactBolus())
        advancePastTheFirstBolus()
        stubCurrentBolus(statusId: 1, bolusId: Self.firstBolusId)
        bluetooth.resetRecordedTraffic()

        XCTAssertEqual(validationError(enactBolus()), .bolusIsRunning)
        XCTAssertFalse(bluetooth.didSend(BolusPermissionRequest.self))
    }

    func testPastTheLastBolussEstimatedEndABolusIsRefusedWhenThePumpDoesNotSayWhetherItFinished() {
        grantBoluses([Self.firstBolusId, Self.secondBolusId])
        XCTAssertNil(enactBolus())
        advancePastTheFirstBolus()
        bluetooth.stub(CurrentBolusStatusRequest.self) { _ in nil }
        bluetooth.resetRecordedTraffic()

        XCTAssertEqual(validationError(enactBolus()), .bolusIsRunning)
        XCTAssertTrue(bluetooth.didSend(CurrentBolusStatusRequest.self))
        XCTAssertFalse(bluetooth.didSend(BolusPermissionRequest.self))
    }
}
