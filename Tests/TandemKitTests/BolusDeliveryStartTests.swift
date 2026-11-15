import LoopKit
@testable import TandemKit
import XCTest

/// How an accepted bolus moves from `.initiating` to `.inProgress`, and what a relaunch keeps of it.
@available(macOS 13.0, iOS 14.0, *) final class BolusDeliveryStartTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var clock: ManualClock!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!

    private static let bolusId = 6902
    private static let units = 4.7

    private enum PumpBolusStatus: Int {
        case noBolus = 0
        case delivering = 1
        case requesting = 2
    }

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        clock = ManualClock(Date(timeIntervalSinceReferenceDate: 700_000_000))
        start(state: TandemPumpManagerState(rawValue: [:]))
        bluetooth.stub(BolusPermissionRequest.self, with: BolusPermissionResponse(status: 0, bolusId: Self.bolusId, nackReasonId: 0))
        bluetooth.stub(InitiateBolusRequest.self, with: InitiateBolusResponse(status: 0, bolusId: Self.bolusId, statusTypeId: 0))
    }

    override func tearDown() {
        delegateQueue = nil
        delegate = nil
        manager = nil
        clock = nil
        bluetooth = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func start(state: TandemPumpManagerState) {
        manager = TandemPumpManager(state: state, bluetooth: bluetooth, clock: clock)
        manager.bolusStartPollInterval = 0
        delegate = MockPumpManagerDelegate()
        delegateQueue = DispatchQueue(label: "bolus-delivery-start-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}
    }

    private func relaunch() {
        start(state: TandemPumpManagerState(rawValue: manager.state.rawValue))
    }

    private func status(_ status: PumpBolusStatus, bolusId: Int = bolusId) -> CurrentBolusStatusResponse {
        CurrentBolusStatusResponse(
            statusId: status.rawValue,
            bolusId: status == .noBolus ? 0 : bolusId,
            timestamp: 0,
            requestedVolume: UInt32(Self.units * 1000),
            bolusSourceId: 8,
            bolusTypeBitmask: 9
        )
    }

    private func enactBolus() -> PumpManagerError? {
        let finished = expectation(description: "enactBolus")
        var result: PumpManagerError?
        manager.enactBolus(decisionId: nil, units: Self.units, activationType: .manualNoRecommendation) {
            result = $0
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5.0)
        delegateQueue.sync {}
        return result
    }

    private var isInProgress: Bool {
        if case .inProgress = manager.status.bolusState { return true }
        return false
    }

    private var statusReads: Int {
        bluetooth.sent(CurrentBolusStatusRequest.self).count
    }

    // MARK: - After the pump accepts

    func testAnAcceptedBolusTurnsInProgressAsSoonAsThePumpDeliversIt() {
        bluetooth.enqueue(CurrentBolusStatusRequest.self, responses: [status(.requesting), status(.requesting), status(.delivering)])

        XCTAssertNil(enactBolus())

        XCTAssertTrue(isInProgress, "\(manager.status.bolusState)")
        XCTAssertEqual(statusReads, 3)
        XCTAssertNotNil(manager.state.bolusDose?.deliveryStartDate)
    }

    func testTheHostSeesInitiatingBeforeInProgress() {
        bluetooth.enqueue(CurrentBolusStatusRequest.self, responses: [status(.requesting), status(.delivering)])

        XCTAssertNil(enactBolus())

        let states = delegate.statusUpdates.map(\.newStatus.bolusState)
        let initiating = states.firstIndex(of: .initiating)
        let inProgress = states.firstIndex { if case .inProgress = $0 { return true } else { return false } }
        XCTAssertNotNil(initiating, "\(states)")
        XCTAssertNotNil(inProgress, "\(states)")
        XCTAssertLessThan(initiating ?? .max, inProgress ?? .min)
    }

    func testTheHostHasItsAnswerBeforeThePumpIsAskedAboutTheBolus() {
        bluetooth.stub(CurrentBolusStatusRequest.self, with: status(.delivering))
        var answered = false
        var answeredAtFirstRead: Bool?
        bluetooth.onWrite = { message in
            if message is CurrentBolusStatusRequest, answeredAtFirstRead == nil {
                answeredAtFirstRead = answered
            }
        }
        let finished = expectation(description: "enactBolus")
        manager.enactBolus(decisionId: nil, units: Self.units, activationType: .manualNoRecommendation) { _ in
            answered = true
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5.0)

        XCTAssertEqual(answeredAtFirstRead, true)
    }

    func testTheProgressReporterTheHostHeldThroughInitiatingIsTheOneThatReportsDelivery() {
        bluetooth.enqueue(CurrentBolusStatusRequest.self, responses: [status(.requesting), status(.delivering)])
        var reporterAtInitiating: TandemDoseProgressReporter?
        bluetooth.onWrite = { [unowned self] message in
            if message is CurrentBolusStatusRequest, reporterAtInitiating == nil {
                reporterAtInitiating = self.manager.bolusProgressReport
            }
        }

        XCTAssertNil(enactBolus())

        XCTAssertNotNil(reporterAtInitiating)
        XCTAssertTrue(reporterAtInitiating === manager.bolusProgressReport)
    }

    func testAnAnswerOfNoBolusLeavesTheAcceptedBolusInitiating() {
        bluetooth.stub(CurrentBolusStatusRequest.self, with: status(.noBolus))

        XCTAssertNil(enactBolus())

        XCTAssertEqual(manager.status.bolusState, .initiating)
        XCTAssertEqual(manager.state.bolusDose?.bolusId, Self.bolusId)
        XCTAssertNil(manager.state.pendingBolusFinalization)
        XCTAssertEqual(statusReads, 1)
    }

    func testAnotherBolusDeliveringLeavesTheAcceptedBolusInitiating() {
        bluetooth.stub(CurrentBolusStatusRequest.self, with: status(.delivering, bolusId: Self.bolusId - 1))

        XCTAssertNil(enactBolus())

        XCTAssertEqual(manager.status.bolusState, .initiating)
        XCTAssertEqual(manager.state.bolusDose?.bolusId, Self.bolusId)
        XCTAssertEqual(statusReads, 1)
    }

    func testAnUnansweredReadLeavesTheAcceptedBolusInitiating() {
        bluetooth.stub(CurrentBolusStatusRequest.self) { _ in nil }

        XCTAssertNil(enactBolus())

        XCTAssertEqual(manager.status.bolusState, .initiating)
        XCTAssertEqual(statusReads, 1)
    }

    func testThePumpIsAskedNoMoreThanTheLimitWhileItKeepsRequesting() {
        bluetooth.stub(CurrentBolusStatusRequest.self, with: status(.requesting))

        XCTAssertNil(enactBolus())

        XCTAssertEqual(manager.status.bolusState, .initiating)
        XCTAssertEqual(statusReads, TandemPumpManager.bolusStartPollLimit)
    }

    func testACancelAskedForWhileThePumpRequestsGoesOutAfterOneMoreRead() {
        bluetooth.stub(CurrentBolusStatusRequest.self, with: status(.requesting))
        bluetooth.stub(CancelBolusRequest.self, with: CancelBolusResponse(statusId: 0, bolusId: Self.bolusId, reasonId: 0))
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        let cancelled = expectation(description: "cancelBolus")
        var askedToCancel = false
        bluetooth.onWrite = { [unowned self] message in
            guard message is CurrentBolusStatusRequest, !askedToCancel else { return }
            askedToCancel = true
            self.manager.cancelBolus { _ in cancelled.fulfill() }
        }

        XCTAssertNil(enactBolus())
        wait(for: [cancelled], timeout: 15.0)

        XCTAssertEqual(statusReads, 1)
        XCTAssertTrue(bluetooth.didSend(CancelBolusRequest.self))
    }

    func testAnUncertainBolusIsNotFollowed() {
        bluetooth.stub(InitiateBolusRequest.self) { _ in nil }
        bluetooth.stub(CurrentBolusStatusRequest.self) { _ in nil }

        guard case .uncertainDelivery? = enactBolus() else {
            return XCTFail("expected uncertainDelivery")
        }

        XCTAssertEqual(statusReads, 1, "only settleUnansweredBolus's own read")
    }

    // MARK: - Relaunch

    func testARelaunchMidBolusGivesTheHostAReporterCountingFromTheDeliveryStart() throws {
        bluetooth.stub(CurrentBolusStatusRequest.self, with: status(.delivering))
        XCTAssertNil(enactBolus())
        let deliveryStart = try XCTUnwrap(manager.state.bolusDose?.deliveryStartDate)
        clock.advance(by: 10)

        relaunch()

        let reporter = try XCTUnwrap(manager.createBolusProgressReporter(reportingOn: delegateQueue))
        manager.bolusProgressReport?.notify()
        let expected = TandemPumpCapabilities.roundToReportingResolution(
            clock.now.timeIntervalSince(deliveryStart) * TandemPumpCapabilities.bolusSpeedUnder10U
        )
        XCTAssertEqual(reporter.progress.deliveredUnits, expected, accuracy: 0.0005)
        XCTAssertGreaterThan(reporter.progress.deliveredUnits, 0)
    }

    func testARelaunchBeforeDeliveryStartsGivesTheHostAReporterAtZero() throws {
        bluetooth.stub(CurrentBolusStatusRequest.self) { _ in nil }
        XCTAssertNil(enactBolus())
        XCTAssertEqual(manager.status.bolusState, .initiating)

        relaunch()

        let reporter = try XCTUnwrap(manager.createBolusProgressReporter(reportingOn: delegateQueue))
        XCTAssertEqual(reporter.progress.deliveredUnits, 0)
        XCTAssertEqual(manager.status.bolusState, .initiating)
    }

    func testARelaunchWithAnUnconfirmedBolusGivesNoReporter() {
        bluetooth.stub(InitiateBolusRequest.self) { _ in nil }
        bluetooth.stub(CurrentBolusStatusRequest.self) { _ in nil }
        _ = enactBolus()
        XCTAssertEqual(manager.state.bolusDose?.isUnconfirmed, true)

        relaunch()

        XCTAssertNil(manager.createBolusProgressReporter(reportingOn: delegateQueue))
    }
}
