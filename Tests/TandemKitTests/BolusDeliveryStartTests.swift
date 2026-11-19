import LoopKit
@testable import TandemKit
import XCTest

/// How a bolus moves through `.initiating` and `.inProgress` under each host, and what a relaunch keeps of it.
@available(macOS 13.0, iOS 14.0, *) final class BolusDeliveryStartTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var clock: ManualClock!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!
    private var hostApp: HostApp = .trio

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
        manager.hostApp = hostApp
        delegate = MockPumpManagerDelegate()
        delegateQueue = DispatchQueue(label: "bolus-delivery-start-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}
    }

    private func runUnder(_ host: HostApp) {
        hostApp = host
        manager.hostApp = host
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

    func testUnderTrioAnAcceptedBolusTurnsInProgressAsSoonAsThePumpDeliversIt() {
        bluetooth.enqueue(CurrentBolusStatusRequest.self, responses: [status(.requesting), status(.requesting), status(.delivering)])

        XCTAssertNil(enactBolus())

        XCTAssertTrue(isInProgress, "\(manager.status.bolusState)")
        XCTAssertEqual(statusReads, 3)
        XCTAssertNotNil(manager.state.bolusDose?.deliveryStartDate)
    }

    func testUnderTrioTheHostSeesInitiatingBeforeInProgress() {
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

    // MARK: - Under Loop

    private func bolusStateAtWrite(of requestType: Message.Type) -> () -> PumpManagerStatus.BolusState? {
        var seen: PumpManagerStatus.BolusState?
        bluetooth.onWrite = { [unowned self] message in
            if type(of: message) == requestType, seen == nil {
                seen = self.manager.status.bolusState
            }
        }
        return { seen }
    }

    func testUnderLoopTheBolusIsStartingWhileItsCommandGoesOut() {
        runUnder(.loop)
        bluetooth.stub(CurrentBolusStatusRequest.self, with: status(.requesting))
        let atInitiate = bolusStateAtWrite(of: InitiateBolusRequest.self)

        XCTAssertNil(enactBolus())

        XCTAssertEqual(atInitiate(), .initiating)
    }

    func testUnderLoopAnAcceptedBolusIsInProgressBeforeThePumpDeliversIt() throws {
        runUnder(.loop)
        bluetooth.stub(CurrentBolusStatusRequest.self, with: status(.requesting))

        XCTAssertNil(enactBolus())

        XCTAssertTrue(isInProgress, "\(manager.status.bolusState)")
        XCTAssertNil(manager.state.bolusDose?.deliveryStartDate)
        let reporter = try XCTUnwrap(manager.createBolusProgressReporter(reportingOn: delegateQueue))
        XCTAssertEqual(reporter.progress.deliveredUnits, 0)
    }

    func testUnderLoopTheHostGoesFromStartingToInProgressWithNothingBetween() {
        runUnder(.loop)
        bluetooth.stub(CurrentBolusStatusRequest.self, with: status(.requesting))

        XCTAssertNil(enactBolus())

        let states = delegate.statusUpdates.map(\.newStatus.bolusState)
        let initiating = states.firstIndex(of: .initiating)
        let inProgress = states.firstIndex { if case .inProgress = $0 { return true } else { return false } }
        XCTAssertNotNil(initiating, "\(states)")
        XCTAssertNotNil(inProgress, "\(states)")
        XCTAssertEqual((initiating ?? 0) + 1, inProgress, "\(states)")
    }

    func testUnderLoopTheProgressCountStartsWhenThePumpDelivers() {
        runUnder(.loop)
        bluetooth.enqueue(CurrentBolusStatusRequest.self, responses: [status(.requesting), status(.delivering)])

        XCTAssertNil(enactBolus())

        XCTAssertEqual(statusReads, 2)
        XCTAssertNotNil(manager.state.bolusDose?.deliveryStartDate)
        XCTAssertNotNil(manager.bolusProgressReport?.bolusStatedOn)
    }

    func testUnderLoopARefusedPermissionClearsStartingBolus() {
        runUnder(.loop)
        bluetooth.stub(BolusPermissionRequest.self, with: BolusPermissionResponse(status: 1, bolusId: 0, nackReasonId: 1))

        XCTAssertNotNil(enactBolus())

        XCTAssertEqual(manager.status.bolusState, .noBolus)
        XCTAssertEqual(delegate.statusUpdates.map(\.newStatus.bolusState).last, .noBolus)
        XCTAssertTrue(delegate.statusUpdates.contains { $0.newStatus.bolusState == .initiating })
    }

    func testUnderLoopARefusedBolusClearsStartingBolus() {
        runUnder(.loop)
        bluetooth.stub(InitiateBolusRequest.self, with: InitiateBolusResponse(status: 1, bolusId: Self.bolusId, statusTypeId: 1))

        XCTAssertNotNil(enactBolus())

        XCTAssertEqual(manager.status.bolusState, .noBolus)
        XCTAssertNil(manager.state.bolusDose)
    }

    func testUnderLoopAnUncertainBolusStaysInitiating() {
        runUnder(.loop)
        bluetooth.stub(InitiateBolusRequest.self) { _ in nil }
        bluetooth.stub(CurrentBolusStatusRequest.self) { _ in nil }

        guard case .uncertainDelivery? = enactBolus() else {
            return XCTFail("expected uncertainDelivery")
        }

        XCTAssertEqual(manager.status.bolusState, .initiating)
    }

    func testUnderTrioNothingIsReportedWhileTheCommandGoesOut() {
        bluetooth.stub(CurrentBolusStatusRequest.self, with: status(.requesting))
        let atInitiate = bolusStateAtWrite(of: InitiateBolusRequest.self)

        XCTAssertNil(enactBolus())

        XCTAssertEqual(atInitiate(), .noBolus)
        XCTAssertEqual(manager.status.bolusState, .initiating)
    }

    func testUnderLoopARelaunchBeforeDeliveryKeepsTheBolusInProgress() throws {
        runUnder(.loop)
        bluetooth.stub(CurrentBolusStatusRequest.self) { _ in nil }
        XCTAssertNil(enactBolus())

        relaunch()

        XCTAssertTrue(isInProgress, "\(manager.status.bolusState)")
        XCTAssertNotNil(manager.createBolusProgressReporter(reportingOn: delegateQueue))
    }

    // MARK: - Cancel

    private func stubLastBolus(bolusId: Int, deliveredMilliunits: UInt32) {
        bluetooth.stub(LastBolusStatusRequest.self, with: LastBolusStatusResponse(
            status: 0,
            bolusId: bolusId,
            timestamp: 0,
            deliveredVolume: deliveredMilliunits,
            bolusStatusId: 3,
            bolusSourceId: 8,
            bolusTypeBitmask: 0,
            extendedBolusDuration: 0
        ))
    }

    private func cancelBolus() -> PumpManagerResult<DoseEntry?> {
        let cancelled = expectation(description: "cancelBolus")
        var result: PumpManagerResult<DoseEntry?>!
        manager.cancelBolus {
            result = $0
            cancelled.fulfill()
        }
        wait(for: [cancelled], timeout: 15.0)
        delegateQueue.sync {}
        return result
    }

    private func stubCancel(succeeds: Bool) {
        bluetooth.stub(CancelBolusRequest.self, with: CancelBolusResponse(
            statusId: succeeds ? 0 : 1,
            bolusId: Self.bolusId,
            reasonId: succeeds ? 0 : 2
        ))
    }

    private var lastReportedBolus: NewPumpEvent? {
        delegate.pumpEventBatches.flatMap(\.events).last { $0.dose?.type == .bolus }
    }

    func testACancelBeforeThePumpStartsTheBolusIsFinalizedAtNothingDelivered() throws {
        runUnder(.loop)
        bluetooth.stub(CurrentBolusStatusRequest.self, with: status(.requesting))
        XCTAssertNil(enactBolus())
        stubCancel(succeeds: true)
        stubLastBolus(bolusId: Self.bolusId - 1, deliveredMilliunits: 1000)

        guard case let .success(dose) = cancelBolus() else {
            return XCTFail("cancel failed")
        }

        XCTAssertEqual(dose?.deliveredUnits, 0)
        XCTAssertEqual(dose?.isMutable, false)
        let reported = try XCTUnwrap(lastReportedBolus?.dose)
        XCTAssertEqual(reported.deliveredUnits, 0)
        XCTAssertFalse(reported.isMutable)
        XCTAssertNil(manager.state.pendingBolusFinalization)
        XCTAssertEqual(manager.status.bolusState, .noBolus)
    }

    func testACancelLongAfterTheLastRequestingReadIsHeld() {
        runUnder(.loop)
        bluetooth.stub(CurrentBolusStatusRequest.self, with: status(.requesting))
        XCTAssertNil(enactBolus())
        clock.advance(by: TandemPumpManager.requestingReadEvidenceWindow + 1)
        stubCancel(succeeds: true)
        stubLastBolus(bolusId: Self.bolusId - 1, deliveredMilliunits: 1000)

        guard case let .success(dose) = cancelBolus() else {
            return XCTFail("cancel failed")
        }

        XCTAssertEqual(dose?.isMutable, true)
        XCTAssertEqual(manager.state.pendingBolusFinalization?.bolusId, Self.bolusId)
    }

    func testACancelOfABolusSeenDeliveringIsHeldWhenThePumpStoredNothingOfIt() throws {
        runUnder(.loop)
        bluetooth.stub(CurrentBolusStatusRequest.self, with: status(.delivering))
        XCTAssertNil(enactBolus())
        clock.advance(by: 5)
        stubCancel(succeeds: true)
        stubLastBolus(bolusId: Self.bolusId - 1, deliveredMilliunits: 1000)

        guard case let .success(dose) = cancelBolus() else {
            return XCTFail("cancel failed")
        }

        XCTAssertEqual(dose?.isMutable, true)
        XCTAssertEqual(manager.state.pendingBolusFinalization?.bolusId, Self.bolusId)
    }

    func testACancelWhoseLastBolusIsUnreadableIsHeldEvenBeforeDelivery() {
        runUnder(.loop)
        bluetooth.stub(CurrentBolusStatusRequest.self, with: status(.requesting))
        XCTAssertNil(enactBolus())
        stubCancel(succeeds: true)
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }

        guard case let .success(dose) = cancelBolus() else {
            return XCTFail("cancel failed")
        }

        XCTAssertEqual(dose?.isMutable, true)
        XCTAssertEqual(manager.state.pendingBolusFinalization?.bolusId, Self.bolusId)
    }

    func testUnderLoopTheBolusIsCancelingFromTheTapUntilThePumpAnswers() {
        runUnder(.loop)
        bluetooth.stub(CurrentBolusStatusRequest.self, with: status(.requesting))
        XCTAssertNil(enactBolus())
        stubCancel(succeeds: true)
        stubLastBolus(bolusId: Self.bolusId - 1, deliveredMilliunits: 1000)
        let atCancel = bolusStateAtWrite(of: CancelBolusRequest.self)

        _ = cancelBolus()

        XCTAssertEqual(atCancel(), .canceling)
        XCTAssertEqual(manager.status.bolusState, .noBolus)
    }

    func testUnderLoopACancelThePumpRefusesGoesBackToInProgress() {
        runUnder(.loop)
        bluetooth.stub(CurrentBolusStatusRequest.self, with: status(.requesting))
        XCTAssertNil(enactBolus())
        stubCancel(succeeds: false)

        guard case .failure = cancelBolus() else {
            return XCTFail("expected the refusal")
        }

        XCTAssertTrue(isInProgress, "\(manager.status.bolusState)")
        XCTAssertEqual(manager.state.bolusDose?.bolusId, Self.bolusId)
    }

    func testUnderLoopADeliveringReadWhileCancelingKeepsItCanceling() {
        runUnder(.loop)
        bluetooth.stub(CurrentBolusStatusRequest.self, with: status(.requesting))
        XCTAssertNil(enactBolus())
        manager.state.bolusState = .canceling

        manager.applyBolusStatus(status(.delivering))

        XCTAssertEqual(manager.status.bolusState, .canceling)
        XCTAssertNotNil(manager.state.bolusDose?.deliveryStartDate)
    }

    func testUnderTrioACancelLeavesTheBolusStateAlone() {
        bluetooth.stub(CurrentBolusStatusRequest.self, with: status(.requesting))
        XCTAssertNil(enactBolus())
        stubCancel(succeeds: true)
        stubLastBolus(bolusId: Self.bolusId - 1, deliveredMilliunits: 1000)
        let atCancel = bolusStateAtWrite(of: CancelBolusRequest.self)

        _ = cancelBolus()

        XCTAssertEqual(atCancel(), .initiating)
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
