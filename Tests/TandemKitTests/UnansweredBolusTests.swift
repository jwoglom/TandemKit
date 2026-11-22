import LoopKit
@testable import TandemKit
import XCTest

/// `enactBolus` when the pump does not answer `InitiateBolus` (#327).
@available(macOS 13.0, iOS 14.0, *) final class UnansweredBolusTests: XCTestCase {
    private static let pumpSerial: UInt32 = 123_456
    private static let bolusId = 4200
    private static let units = 2.0

    private var bluetooth: StubPumpBluetooth!
    private var clock: ManualClock!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        clock = ManualClock(Date(timeIntervalSinceReferenceDate: 700_000_000))
        var state = TandemPumpManagerState(rawValue: [:])
        state.pumpState.pumpSerial = Self.pumpSerial
        state.bolusReportLedger = BolusReportLedger(trackingSince: .distantPast)
        manager = makeManager(state: state)
    }

    override func tearDown() {
        delegate = nil
        manager = nil
        clock = nil
        bluetooth = nil
        super.tearDown()
    }

    private func makeManager(state: TandemPumpManagerState) -> TandemPumpManager {
        let manager = TandemPumpManager(state: state, bluetooth: bluetooth, clock: clock)
        delegate = MockPumpManagerDelegate()
        delegate.journalClock = clock
        manager.pumpManagerDelegate = delegate
        manager.waitForDelegateCalls()
        return manager
    }

    // MARK: - Helpers

    private func grantBolusAndLoseTheAnswer(bolusIds: [Int] = [bolusId]) {
        bluetooth.enqueue(BolusPermissionRequest.self, responses: bolusIds.map {
            BolusPermissionResponse(status: 0, bolusId: $0, nackReasonId: 0)
        })
        bluetooth.stub(InitiateBolusRequest.self) { _ in nil }
        bluetooth.stub(BolusPermissionReleaseRequest.self, with: BolusPermissionReleaseResponse(status: 0))
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

    private func stubCurrentBolus(statusId: Int, bolusId: Int) {
        bluetooth.stub(CurrentBolusStatusRequest.self, with: CurrentBolusStatusResponse(
            statusId: statusId,
            bolusId: bolusId,
            timestamp: 0,
            requestedVolume: UInt32(Self.units * 1000),
            bolusSourceId: 8,
            bolusTypeBitmask: 0
        ))
    }

    private func stubNoBolusRunning() {
        stubCurrentBolus(statusId: 0, bolusId: 0)
    }

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

    /// An unconfirmed bolus: the pump answered neither `InitiateBolus` nor the status read after it.
    private func registerUnconfirmedBolus() throws -> NewPumpEvent {
        grantBolusAndLoseTheAnswer()
        bluetooth.stub(CurrentBolusStatusRequest.self) { _ in nil }

        XCTAssertTrue(isUncertainDelivery(enactBolus()))
        bluetooth.resetRecordedTraffic()
        return try XCTUnwrap(reportedBoluses.last)
    }

    private func readBolusStatus() {
        manager.fetchBolusStatus(fromSync: true)
        manager.waitForDelegateCalls()
    }

    private var reportedBoluses: [NewPumpEvent] {
        manager.waitForDelegateCalls()
        return delegate.pumpEventBatches.flatMap(\.events).filter { $0.dose?.type == .bolus }
    }

    private func isUncertainDelivery(_ error: PumpManagerError?) -> Bool {
        guard case .uncertainDelivery? = error else { return false }
        return true
    }

    private func validationError(_ error: PumpManagerError?) -> TandemPumpManagerValidationError? {
        guard case let .deviceState(underlying?)? = error else { return nil }
        return underlying as? TandemPumpManagerValidationError
    }

    private func ledgerEntry() -> BolusReportLedger.Entry? {
        manager.state.bolusReportLedger.entry(bolusId: Self.bolusId, pumpSerial: Self.pumpSerial)
    }

    // MARK: - Settled while enacting

    func testAnUnansweredBolusThePumpIsDeliveringIsReportedAsEnacted() throws {
        grantBolusAndLoseTheAnswer()
        stubCurrentBolus(statusId: 1, bolusId: Self.bolusId)

        XCTAssertNil(enactBolus())

        let dose = try XCTUnwrap(manager.state.bolusDose)
        XCTAssertEqual(dose.bolusId, Self.bolusId)
        XCTAssertFalse(dose.isUnconfirmed)
        XCTAssertFalse(manager.status.deliveryIsUncertain)
        XCTAssertNotNil(manager.bolusProgressReport)
        let event = try XCTUnwrap(reportedBoluses.last)
        XCTAssertEqual(event.dose?.isMutable, true)
        XCTAssertEqual(event.dose?.programmedUnits, Self.units)
        XCTAssertFalse(bluetooth.didSend(BolusPermissionReleaseRequest.self))
    }

    func testAnUnansweredBolusThePumpHasAlreadyFinishedIsReportedAsEnacted() {
        grantBolusAndLoseTheAnswer()
        stubNoBolusRunning()
        stubLastBolus(bolusId: Self.bolusId, deliveredMilliunits: 2000)

        XCTAssertNil(enactBolus())

        XCTAssertEqual(manager.state.bolusDose?.bolusId, Self.bolusId)
        XCTAssertFalse(manager.status.deliveryIsUncertain)
        XCTAssertFalse(bluetooth.didSend(BolusPermissionReleaseRequest.self))
    }

    func testAnUnansweredBolusThePumpNeverStartedFailsAndReleasesItsPermission() {
        grantBolusAndLoseTheAnswer()
        stubNoBolusRunning()
        stubLastBolus(bolusId: Self.bolusId - 1, deliveredMilliunits: 1000)

        let error = enactBolus()

        guard case .communication? = error else {
            return XCTFail("got \(String(describing: error))")
        }
        XCTAssertNil(manager.state.bolusDose)
        XCTAssertEqual(manager.state.bolusState, .noBolus)
        XCTAssertFalse(manager.status.deliveryIsUncertain)
        XCTAssertTrue(reportedBoluses.isEmpty)
        XCTAssertNil(ledgerEntry())
        XCTAssertEqual(bluetooth.sent(BolusPermissionReleaseRequest.self).map(\.bolusID), [Self.bolusId])
    }

    func testAnUnansweredBolusThePumpCannotBeAskedAboutIsReportedAsUncertainDelivery() throws {
        grantBolusAndLoseTheAnswer()
        bluetooth.stub(CurrentBolusStatusRequest.self) { _ in nil }

        let error = enactBolus()

        XCTAssertTrue(isUncertainDelivery(error), "got \(String(describing: error))")
        let dose = try XCTUnwrap(manager.state.bolusDose)
        XCTAssertEqual(dose.bolusId, Self.bolusId)
        XCTAssertTrue(dose.isUnconfirmed)
        XCTAssertTrue(manager.status.deliveryIsUncertain)
        XCTAssertNil(manager.bolusProgressReport, "nothing reports progress of a bolus the pump may not be running")
        XCTAssertFalse(bluetooth.didSend(BolusPermissionReleaseRequest.self))

        let event = try XCTUnwrap(reportedBoluses.last)
        XCTAssertEqual(event.dose?.isMutable, true)
        XCTAssertEqual(event.dose?.programmedUnits, Self.units)
        XCTAssertEqual(delegate.pumpEventBatches.last?.replacePendingEvents, false)
        XCTAssertTrue(delegate.statusUpdates.contains { $0.newStatus.deliveryIsUncertain && !$0.oldStatus.deliveryIsUncertain })

        let entry = try XCTUnwrap(ledgerEntry())
        XCTAssertEqual(entry.origin, .commanded)
        XCTAssertEqual(entry.raw, event.raw)
        XCTAssertEqual(entry.units, Self.units)
    }

    func testAnUnansweredBolusIsDatedWhenItWasSent() throws {
        let sentAt = clock.now
        grantBolusAndLoseTheAnswer()
        bluetooth.stub(InitiateBolusRequest.self) { _ in
            self.clock.advance(by: .seconds(30))
            return nil
        }
        bluetooth.stub(CurrentBolusStatusRequest.self) { _ in nil }

        _ = enactBolus()

        XCTAssertEqual(try XCTUnwrap(reportedBoluses.last).date, sentAt)
        XCTAssertEqual(manager.state.bolusDose?.startDate, sentAt)
    }

    // MARK: - Settled at the next contact

    func testTheNextReadConfirmsAnUnconfirmedBolusThePumpIsDelivering() throws {
        let registered = try registerUnconfirmedBolus()
        stubCurrentBolus(statusId: 1, bolusId: Self.bolusId)

        readBolusStatus()

        let dose = try XCTUnwrap(manager.state.bolusDose)
        XCTAssertFalse(dose.isUnconfirmed)
        XCTAssertFalse(manager.status.deliveryIsUncertain)
        guard case .inProgress = manager.status.bolusState else {
            return XCTFail("got \(manager.status.bolusState)")
        }
        XCTAssertNotNil(manager.bolusProgressReport)
        XCTAssertTrue(delegate.statusUpdates.contains { !$0.newStatus.deliveryIsUncertain && $0.oldStatus.deliveryIsUncertain })
        XCTAssertEqual(reportedBoluses.map(\.raw), [registered.raw])
    }

    func testTheNextReadFinalizesAnUnconfirmedBolusThePumpFinishedAtWhatItDelivered() throws {
        let registered = try registerUnconfirmedBolus()
        stubNoBolusRunning()
        stubLastBolus(bolusId: Self.bolusId, deliveredMilliunits: 1850)

        readBolusStatus()

        let finalized = try XCTUnwrap(reportedBoluses.last)
        XCTAssertEqual(finalized.raw, registered.raw)
        XCTAssertEqual(finalized.dose?.isMutable, false)
        XCTAssertEqual(finalized.dose?.deliveredUnits, 1.85)
        XCTAssertEqual(delegate.pumpEventBatches.last?.replacePendingEvents, true)
        XCTAssertNil(manager.state.bolusDose)
        XCTAssertFalse(manager.status.deliveryIsUncertain)
        XCTAssertEqual(ledgerEntry()?.isFinalized, true)
    }

    func testTheNextReadReportsAnUnconfirmedBolusThePumpNeverStartedAsNothingDelivered() throws {
        let registered = try registerUnconfirmedBolus()
        stubNoBolusRunning()
        stubLastBolus(bolusId: Self.bolusId - 1, deliveredMilliunits: 1000)

        readBolusStatus()

        let finalized = try XCTUnwrap(reportedBoluses.last)
        XCTAssertEqual(finalized.raw, registered.raw)
        XCTAssertEqual(finalized.dose?.isMutable, false)
        XCTAssertEqual(finalized.dose?.deliveredUnits, 0)
        XCTAssertEqual(delegate.pumpEventBatches.last?.replacePendingEvents, true)
        XCTAssertNil(manager.state.bolusDose)
        XCTAssertNil(manager.state.pendingBolusFinalization)
        XCTAssertEqual(manager.status.bolusState, .noBolus)
        XCTAssertFalse(manager.status.deliveryIsUncertain)
        XCTAssertEqual(ledgerEntry()?.isFinalized, true)
        XCTAssertEqual(ledgerEntry()?.units, 0)
        XCTAssertEqual(bluetooth.sent(BolusPermissionReleaseRequest.self).map(\.bolusID), [Self.bolusId])

        let (loop, trio) = (LoopDoseStoreOracle(), TrioDoseStoreOracle())
        delegate.feed(loop)
        delegate.feed(trio)
        loop.assertDeleted(raw: registered.raw)
        XCTAssertTrue(loop.doses.filter { $0.dose.type == .bolus }.isEmpty)
        trio.assertNoDuplicates()
    }

    func testABolusLaterThanAnUnconfirmedOneHoldsItAtItsProgrammedAmount() throws {
        let registered = try registerUnconfirmedBolus()
        stubNoBolusRunning()
        stubLastBolus(bolusId: Self.bolusId + 1, deliveredMilliunits: 500)

        readBolusStatus()

        let held = try XCTUnwrap(manager.state.pendingBolusFinalization)
        XCTAssertEqual(held.bolusId, Self.bolusId)
        XCTAssertEqual(held.deliveredUnits, Self.units, "counted as delivered until the pump's history says otherwise")
        XCTAssertFalse(held.isUnconfirmed)
        XCTAssertNil(manager.state.bolusDose)
        XCTAssertFalse(manager.status.deliveryIsUncertain)
        let event = try XCTUnwrap(reportedBoluses.last)
        XCTAssertEqual(event.raw, registered.raw)
        XCTAssertEqual(event.dose?.isMutable, true)
        XCTAssertFalse(bluetooth.didSend(BolusPermissionReleaseRequest.self))
    }

    func testAnUnconfirmedBolusStaysUncertainWhileThePumpCannotSay() throws {
        _ = try registerUnconfirmedBolus()
        let batches = delegate.pumpEventBatches.count
        stubNoBolusRunning()
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }

        readBolusStatus()

        XCTAssertEqual(manager.state.bolusDose?.isUnconfirmed, true)
        XCTAssertTrue(manager.status.deliveryIsUncertain)
        XCTAssertEqual(delegate.pumpEventBatches.count, batches)
    }

    func testASyncAsksThePumpAboutAnUnconfirmedBolusBeforeItsEstimatedEnd() throws {
        _ = try registerUnconfirmedBolus()
        XCTAssertGreaterThan(try XCTUnwrap(manager.state.bolusDose).estimatedEndDate, clock.now)
        stubCurrentBolus(statusId: 1, bolusId: Self.bolusId)

        readBolusStatus()

        XCTAssertTrue(bluetooth.didSend(CurrentBolusStatusRequest.self))
        XCTAssertFalse(manager.status.deliveryIsUncertain)
    }

    func testAHostPollIsNotThrottledWhileABolusIsUnconfirmed() throws {
        _ = try registerUnconfirmedBolus()
        manager.state.isConnected = true
        stubCurrentBolus(statusId: 1, bolusId: Self.bolusId)

        let synced = expectation(description: "ensureCurrentPumpData")
        manager.ensureCurrentPumpData { _ in synced.fulfill() }
        wait(for: [synced], timeout: 5.0)
        manager.waitForDelegateCalls()

        XCTAssertTrue(bluetooth.didSend(CurrentBolusStatusRequest.self))
        XCTAssertFalse(manager.status.deliveryIsUncertain)
    }

    func testAHostPollIsThrottledOnceTheBolusIsConfirmed() throws {
        _ = try registerUnconfirmedBolus()
        manager.state.isConnected = true
        stubCurrentBolus(statusId: 1, bolusId: Self.bolusId)
        readBolusStatus()
        bluetooth.resetRecordedTraffic()

        let synced = expectation(description: "ensureCurrentPumpData")
        manager.ensureCurrentPumpData { _ in synced.fulfill() }
        wait(for: [synced], timeout: 5.0)

        XCTAssertEqual(bluetooth.ensureConnectedCount, 0)
    }

    // MARK: - The next bolus

    func testTheNextBolusAsksThePumpAboutAnUnconfirmedOneAndGoesOutIfItNeverStarted() throws {
        grantBolusAndLoseTheAnswer(bolusIds: [Self.bolusId, Self.bolusId + 1])
        bluetooth.stub(CurrentBolusStatusRequest.self) { _ in nil }
        XCTAssertTrue(isUncertainDelivery(enactBolus()))
        stubNoBolusRunning()
        stubLastBolus(bolusId: Self.bolusId - 1, deliveredMilliunits: 1000)
        bluetooth.stub(InitiateBolusRequest.self) { request in
            InitiateBolusResponse(status: 0, bolusId: (request as! InitiateBolusRequest).bolusID, statusTypeId: 0)
        }
        bluetooth.resetRecordedTraffic()

        XCTAssertNil(enactBolus())

        XCTAssertTrue(bluetooth.sentMessages.first is CurrentBolusStatusRequest, "\(bluetooth.sentMessages)")
        XCTAssertEqual(bluetooth.sent(InitiateBolusRequest.self).map(\.bolusID), [Self.bolusId + 1])
        XCTAssertEqual(manager.state.bolusDose?.bolusId, Self.bolusId + 1)
        XCTAssertFalse(manager.status.deliveryIsUncertain)
    }

    func testTheNextBolusIsRefusedOnceThePumpConfirmsTheUnconfirmedOneIsRunning() throws {
        _ = try registerUnconfirmedBolus()
        stubCurrentBolus(statusId: 1, bolusId: Self.bolusId)

        XCTAssertEqual(validationError(enactBolus()), .bolusIsRunning)

        XCTAssertFalse(bluetooth.didSend(BolusPermissionRequest.self))
        XCTAssertFalse(manager.status.deliveryIsUncertain)
    }

    func testTheNextBolusIsRefusedWhileThePumpStillCannotSay() throws {
        _ = try registerUnconfirmedBolus()
        bluetooth.stub(CurrentBolusStatusRequest.self) { _ in nil }

        XCTAssertEqual(validationError(enactBolus()), .bolusIsRunning)

        XCTAssertTrue(bluetooth.didSend(CurrentBolusStatusRequest.self))
        XCTAssertFalse(bluetooth.didSend(BolusPermissionRequest.self))
        XCTAssertTrue(manager.status.deliveryIsUncertain)
    }

    // MARK: - Relaunch and history

    func testAnUnconfirmedBolusIsStillUncertainAfterARelaunch() throws {
        let registered = try registerUnconfirmedBolus()

        manager = makeManager(state: TandemPumpManagerState(rawValue: manager.rawState))

        XCTAssertEqual(manager.state.bolusDose?.isUnconfirmed, true)
        XCTAssertTrue(manager.status.deliveryIsUncertain)

        stubNoBolusRunning()
        stubLastBolus(bolusId: Self.bolusId, deliveredMilliunits: 2000)
        readBolusStatus()

        let finalized = try XCTUnwrap(reportedBoluses.last)
        XCTAssertEqual(finalized.raw, registered.raw)
        XCTAssertEqual(finalized.dose?.deliveredUnits, Self.units)
        XCTAssertFalse(manager.status.deliveryIsUncertain)
    }

    func testHistoryFinalizesAnUnconfirmedBolusUnderItsOwnIdentity() throws {
        manager.state.featureFlags[.historyBackfill] = true
        manager.state.featureFlags[.historyDoseReporting] = true
        let registered = try registerUnconfirmedBolus()
        let activated = UInt32(Dates.fromInstantToJan12008EpochSeconds(clock.now)) + 14
        let logs: [HistoryLog] = [
            BolusActivatedHistoryLog(pumpTimeSec: activated, sequenceNum: 10, bolusId: Self.bolusId, selectedIob: 0, iob: 0, bolusSize: 2),
            BolusCompletedHistoryLog(
                pumpTimeSec: activated + 100,
                sequenceNum: 11,
                completionStatusId: 3,
                bolusId: Self.bolusId,
                iob: 2,
                insulinDelivered: 2,
                insulinRequested: 2
            )
        ]
        clock.advance(by: .minutes(3))
        manager.storeHistoryLogs(logs, now: clock.now)

        manager.reportHistoryBoluses(
            in: 10 ... 11,
            pumpSerial: try XCTUnwrap(HistoryLogSyncIdentifier.PumpSerial(Self.pumpSerial)),
            floor: clock.now.addingTimeInterval(-BolusReportLedger.reportingHorizon),
            now: clock.now
        )
        manager.waitForDelegateCalls()

        XCTAssertEqual(Set(reportedBoluses.map(\.raw)), [registered.raw], "one bolus, not a second from history")
        let finalized = try XCTUnwrap(reportedBoluses.last)
        XCTAssertEqual(finalized.dose?.isMutable, false)
        XCTAssertEqual(finalized.dose?.deliveredUnits, 2)
        XCTAssertEqual(finalized.dose?.wasProgrammedByPumpUI, false)
        XCTAssertNil(manager.state.bolusDose)
        XCTAssertFalse(manager.status.deliveryIsUncertain)
    }

    // MARK: - Bolus id order

    func testBolusIdOrderFollowsThePumpsSixteenBitCounter() {
        XCTAssertTrue(TandemPumpManager.bolusId(4199, precedes: 4200))
        XCTAssertFalse(TandemPumpManager.bolusId(4200, precedes: 4200))
        XCTAssertFalse(TandemPumpManager.bolusId(4201, precedes: 4200))
        XCTAssertTrue(TandemPumpManager.bolusId(65535, precedes: 2), "across the wrap")
        XCTAssertFalse(TandemPumpManager.bolusId(2, precedes: 65535))
        XCTAssertTrue(TandemPumpManager.bolusId(0, precedes: 40000), "0 is no bolus at all")
    }

    // pumpStatusHighlight lives in TandemKitUI, which has no Linux build.
    #if canImport(SwiftUI)
    func testAnUnconfirmedBolusIsSurfacedAsAStatusHighlight() throws {
        _ = try registerUnconfirmedBolus()

        let highlight = try XCTUnwrap(manager.pumpStatusHighlight)

        XCTAssertTrue(highlight.localizedMessage.localizedCaseInsensitiveContains("bolus"), "Got: \(highlight.localizedMessage)")
        XCTAssertEqual(highlight.state, .critical)
    }
    #endif
}
