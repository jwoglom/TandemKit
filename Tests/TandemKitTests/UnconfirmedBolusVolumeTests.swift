import LoopKit
@testable import TandemKit
import XCTest

/// What a bolus is finalized with when the pump never confirms its delivered volume (#448): its
/// `BolusCompleted` history record when backfill has read one, otherwise the programmed amount
/// for a bolus the pump finished and an elapsed-time estimate for one cancelled — never the
/// progress reporter's sample, which is 0 U until a second delivering status.
@available(macOS 13.0, iOS 14.0, *) final class UnconfirmedBolusVolumeTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var clock: ManualClock!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!

    private static let t0 = Date(timeIntervalSinceReferenceDate: 700_000_000)
    private static let bolusId = 5120
    private static let pumpSerial: UInt32 = 654_321
    private static let programmedUnits = 2.0

    private var afterTheWindow: Date {
        clock.now.addingTimeInterval(TandemPumpManager.bolusFinalizationWindow + .minutes(1))
    }

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        clock = ManualClock(Self.t0)
        makeManager(state: TandemPumpManagerState(rawValue: [:]))
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

    private func makeManager(state: TandemPumpManagerState) {
        manager = TandemPumpManager(state: state, bluetooth: bluetooth, clock: clock)
        delegate = MockPumpManagerDelegate()
        delegateQueue = DispatchQueue(label: "unconfirmed-bolus-volume-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}
    }

    private func relaunch() {
        makeManager(state: TandemPumpManagerState(rawValue: manager.state.rawValue))
    }

    private func startBolus(units: Double = programmedUnits) {
        bluetooth.stub(BolusPermissionRequest.self, with: BolusPermissionResponse(
            status: 0,
            bolusId: Self.bolusId,
            nackReasonId: 0
        ))
        bluetooth.stub(InitiateBolusRequest.self, with: InitiateBolusResponse(
            status: 0,
            bolusId: Self.bolusId,
            statusTypeId: 0
        ))

        let enacted = expectation(description: "enactBolus")
        manager.enactBolus(units: units, activationType: .manualNoRecommendation) { error in
            XCTAssertNil(error)
            enacted.fulfill()
        }
        wait(for: [enacted], timeout: 5.0)
        delegateQueue.sync {}
        XCTAssertEqual(manager.state.bolusDose?.bolusId, Self.bolusId)
    }

    private func stubNoLastBolus() {
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
    }

    private func stubCurrentBolus(statusId: Int, bolusId: Int, at timestamp: Date? = nil) {
        bluetooth.stub(CurrentBolusStatusRequest.self, with: CurrentBolusStatusResponse(
            statusId: statusId,
            bolusId: bolusId,
            timestamp: timestamp.map { UInt32(Dates.fromInstantToJan12008EpochSeconds($0)) } ?? 0,
            requestedVolume: UInt32(Self.programmedUnits * 1000),
            bolusSourceId: 0,
            bolusTypeBitmask: 0
        ))
    }

    /// Past the bolus's estimated end, where a sync reconciles instead of deferring.
    private func advancePastTheBolus() {
        clock.advance(by: manager.estimatedDuration(toBolus: Self.programmedUnits) + .minutes(2))
    }

    private func storeCompletion(bolusId: Int = bolusId, delivered: Float, at date: Date, sequenceNum: UInt32 = 900) {
        manager.state.pumpState.pumpSerial = Self.pumpSerial
        manager.storeHistoryLogs([BolusCompletedHistoryLog(
            pumpTimeSec: UInt32(Dates.fromInstantToJan12008EpochSeconds(date)),
            sequenceNum: sequenceNum,
            completionStatusId: 3,
            bolusId: bolusId,
            iob: 0,
            insulinDelivered: delivered,
            insulinRequested: Float(Self.programmedUnits)
        )])
    }

    @discardableResult
    private func cancelBolus() -> DoseEntry? {
        bluetooth.stub(CancelBolusRequest.self, with: CancelBolusResponse(
            statusId: 0,
            bolusId: Self.bolusId,
            reasonId: 0
        ))

        var returned: DoseEntry?
        let cancelled = expectation(description: "cancelBolus")
        manager.cancelBolus { result in
            if case .success(let dose) = result {
                returned = dose
            } else {
                XCTFail("cancelBolus failed: \(result)")
            }
            cancelled.fulfill()
        }
        // The cancel path sleeps ~2s to let the pump store the bolus before reading it back.
        wait(for: [cancelled], timeout: 15.0)
        delegateQueue.sync {}
        return returned
    }

    private var finalizedBoluses: [DoseEntry] {
        delegateQueue.sync {}
        return delegate.pumpEvents.compactMap(\.dose).filter { $0.type == .bolus && !$0.isMutable }
    }

    private func finalizedDelivered(file: StaticString = #filePath, line: UInt = #line) throws -> Double {
        let dose = try XCTUnwrap(finalizedBoluses.last, "no finalized bolus", file: file, line: line)
        return try XCTUnwrap(dose.deliveredUnits, file: file, line: line)
    }

    // MARK: - A finished bolus falls back to the programmed amount

    func testCompletionThatNeverSawDeliveryFinalizesAtTheProgrammedAmount() throws {
        startBolus()
        stubNoLastBolus()
        advancePastTheBolus()
        stubCurrentBolus(statusId: 0, bolusId: 0)

        manager.fetchBolusStatus(fromSync: false)
        XCTAssertEqual(manager.state.pendingBolusFinalization?.deliveredUnits, Self.programmedUnits)
        XCTAssertTrue(finalizedBoluses.isEmpty)

        manager.finalizePendingBolus(now: afterTheWindow)

        XCTAssertEqual(try finalizedDelivered(), Self.programmedUnits)
        XCTAssertNil(manager.state.pendingBolusFinalization)
    }

    func testRelaunchedHoldFinalizesAtTheProgrammedAmount() throws {
        startBolus()
        relaunch()
        stubNoLastBolus()
        advancePastTheBolus()
        stubCurrentBolus(statusId: 0, bolusId: 0)

        manager.fetchBolusStatus(fromSync: true)
        XCTAssertEqual(manager.state.pendingBolusFinalization?.deliveredUnits, Self.programmedUnits, "not the persisted 0 U")

        relaunch()
        stubNoLastBolus()
        manager.finalizePendingBolus(now: afterTheWindow)

        XCTAssertEqual(try finalizedDelivered(), Self.programmedUnits)
    }

    func testAnotherBolusDeliveringHoldFinalizesAtTheProgrammedAmount() throws {
        startBolus()
        stubNoLastBolus()
        advancePastTheBolus()
        stubCurrentBolus(statusId: 1, bolusId: Self.bolusId + 1, at: clock.now.addingTimeInterval(-30))

        manager.fetchBolusStatus(fromSync: true)
        XCTAssertEqual(manager.state.pendingBolusFinalization?.bolusId, Self.bolusId)

        manager.finalizePendingBolus(now: afterTheWindow)

        XCTAssertEqual(try finalizedDelivered(), Self.programmedUnits)
    }

    func testAFinishedBolusWithNoDoseToHoldIsReportedAtTheProgrammedAmount() throws {
        let dose = UnfinalizedDose(
            units: Self.programmedUnits,
            duration: 60,
            activationType: .manualNoRecommendation,
            insulinType: .novolog,
            bolusId: Self.bolusId,
            now: clock.now
        )
        manager.bolusProgressReport = TandemDoseProgressReporter(
            pumpManager: manager,
            dose: dose.toDoseEntry(isMutable: true),
            activationType: .manualNoRecommendation
        )
        XCTAssertNil(manager.state.bolusDose)
        stubCurrentBolus(statusId: 0, bolusId: 0)

        manager.fetchBolusStatus(fromSync: false)

        XCTAssertEqual(try finalizedDelivered(), Self.programmedUnits)
    }

    // MARK: - A cancel falls back to the time delivery ran

    func testCancelFallbackIsTheTimeFromDeliveryStartToTheCancel() throws {
        startBolus()
        let deliveryStart = clock.now.addingTimeInterval(15)
        clock.set(deliveryStart.addingTimeInterval(1))
        stubCurrentBolus(statusId: 1, bolusId: Self.bolusId, at: deliveryStart)
        manager.fetchBolusStatus(fromSync: false)
        XCTAssertEqual(manager.state.bolusDose?.deliveryStartDate, deliveryStart)

        clock.set(deliveryStart.addingTimeInterval(20))
        stubNoLastBolus()
        cancelBolus()

        let expected = TandemPumpCapabilities.roundToReportingResolution(TandemPumpCapabilities.unitsDelivered(in: 20, ofBolus: Self.programmedUnits))
        XCTAssertGreaterThan(expected, 0)
        XCTAssertEqual(try XCTUnwrap(manager.state.pendingBolusFinalization?.deliveredUnits), expected, accuracy: 1e-9)

        manager.finalizePendingBolus(now: afterTheWindow)

        XCTAssertEqual(try finalizedDelivered(), expected, accuracy: 1e-9)
    }

    func testCancelBeforeDeliveryWasSeenIsTimedFromProgramming() throws {
        startBolus()
        clock.advance(by: 30)
        stubNoLastBolus()
        cancelBolus()

        manager.finalizePendingBolus(now: afterTheWindow)

        let expected = TandemPumpCapabilities.roundToReportingResolution(TandemPumpCapabilities.unitsDelivered(in: 30, ofBolus: Self.programmedUnits))
        XCTAssertGreaterThan(expected, 0, "no delivering status was ever sampled")
        XCTAssertEqual(try finalizedDelivered(), expected, accuracy: 1e-9)
    }

    func testCancelFallbackNeverExceedsTheProgrammedAmount() throws {
        startBolus()
        clock.advance(by: .hours(1))
        stubNoLastBolus()
        cancelBolus()

        manager.finalizePendingBolus(now: afterTheWindow)

        XCTAssertEqual(try finalizedDelivered(), Self.programmedUnits)
    }

    // MARK: - The pump's history record wins over any fallback

    func testRetryFinalizesFromTheHistoryRecordBeforeTheWindowEnds() throws {
        startBolus()
        stubNoLastBolus()
        advancePastTheBolus()
        stubCurrentBolus(statusId: 0, bolusId: 0)
        manager.fetchBolusStatus(fromSync: false)

        let pumpEnd = Self.t0.addingTimeInterval(120)
        storeCompletion(delivered: 1.234, at: pumpEnd)
        manager.finalizePendingBolus()

        let dose = try XCTUnwrap(finalizedBoluses.last)
        XCTAssertEqual(dose.deliveredUnits, 1.234)
        XCTAssertEqual(dose.endDate.timeIntervalSince(pumpEnd), 0, accuracy: 1.0, "dated by the record")
        XCTAssertNil(manager.state.pendingBolusFinalization)
    }

    func testCancelledBolusIsFinalizedFromItsHistoryRecord() throws {
        startBolus()
        clock.advance(by: 30)
        stubNoLastBolus()
        cancelBolus()

        storeCompletion(delivered: 0.401, at: clock.now)
        manager.finalizePendingBolus()

        XCTAssertEqual(try finalizedDelivered(), 0.401)
    }

    func testHistoryRecordIsUsedAfterARelaunch() throws {
        startBolus()
        relaunch()
        stubNoLastBolus()
        advancePastTheBolus()
        stubCurrentBolus(statusId: 0, bolusId: 0)
        storeCompletion(delivered: 0.75, at: clock.now.addingTimeInterval(-30))

        manager.fetchBolusStatus(fromSync: true)
        manager.finalizePendingBolus()

        XCTAssertEqual(try finalizedDelivered(), 0.75)
    }

    func testAHistoryRecordOfAnotherBolusIsNotUsed() throws {
        startBolus()
        stubNoLastBolus()
        advancePastTheBolus()
        stubCurrentBolus(statusId: 0, bolusId: 0)
        manager.fetchBolusStatus(fromSync: false)
        storeCompletion(bolusId: Self.bolusId + 1, delivered: 0.5, at: clock.now)

        manager.finalizePendingBolus()
        XCTAssertNotNil(manager.state.pendingBolusFinalization, "still waiting for its own record")

        manager.finalizePendingBolus(now: afterTheWindow)
        XCTAssertEqual(try finalizedDelivered(), Self.programmedUnits)
    }

    /// Bolus ids are small counters: a record under the same id from long before is another bolus.
    func testAHistoryRecordFromBeforeTheBolusIsNotUsed() throws {
        startBolus()
        stubNoLastBolus()
        advancePastTheBolus()
        stubCurrentBolus(statusId: 0, bolusId: 0)
        manager.fetchBolusStatus(fromSync: false)
        storeCompletion(delivered: 0.5, at: Self.t0.addingTimeInterval(-.hours(2)))

        manager.finalizePendingBolus(now: afterTheWindow)

        XCTAssertEqual(try finalizedDelivered(), Self.programmedUnits)
    }

    func testHoldingASecondBolusSettlesTheFirstFromItsHistoryRecord() throws {
        startBolus()
        stubNoLastBolus()
        advancePastTheBolus()
        stubCurrentBolus(statusId: 0, bolusId: 0)
        manager.fetchBolusStatus(fromSync: false)
        storeCompletion(delivered: 1.5, at: clock.now)

        let second = UnfinalizedDose(
            units: 1.0,
            duration: 60,
            activationType: .manualNoRecommendation,
            insulinType: nil,
            bolusId: Self.bolusId + 1,
            now: clock.now
        )
        manager.holdForFinalization(second, fallbackUnits: 1.0)

        XCTAssertEqual(try finalizedDelivered(), 1.5)
        XCTAssertEqual(manager.state.pendingBolusFinalization?.bolusId, Self.bolusId + 1)
    }

    // MARK: - Delivery rate model

    func testUnitsDeliveredFollowsThePumpsRate() {
        XCTAssertEqual(TandemPumpCapabilities.unitsDelivered(in: 0, ofBolus: 2), 0)
        XCTAssertEqual(TandemPumpCapabilities.unitsDelivered(in: -5, ofBolus: 2), 0)
        XCTAssertEqual(
            TandemPumpCapabilities.unitsDelivered(in: 10, ofBolus: 2),
            10 * TandemPumpCapabilities.bolusSpeedUnder10U,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            TandemPumpCapabilities.unitsDelivered(in: 10, ofBolus: 12),
            10 * TandemPumpCapabilities.bolusSpeedOver10U,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            TandemPumpCapabilities.unitsDelivered(in: TandemPumpCapabilities.estimatedBolusDuration(toDeliver: 2) * 2, ofBolus: 2),
            2
        )
    }
}
