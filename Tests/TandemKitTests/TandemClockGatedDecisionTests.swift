import Combine
import CoreBluetooth
import Foundation
import LoopKit
@testable import TandemKit
import XCTest

/// Every wall-clock read in the driver goes through the injected `TandemClock`, so a decision that
/// depends on "now" has to be made from the clock at the moment the function *runs*.
///
/// The regression this file exists to catch is a `now` captured too early — stashed in an
/// initializer, frozen into a default argument evaluated once, or read when the manager was built
/// rather than when the dose was stamped. Every test below therefore constructs at T0, moves the
/// clock to a clearly distinguishable T1, and then calls the function: a cached reading shows up as
/// a T0 stamp. The window-gated decisions are additionally driven across both sides of their
/// boundary, and the boundary itself is re-checked after letting the clock run on before the window
/// even opens, which is what distinguishes "measured from the call" from "pre-aged at construction".
///
/// `TandemClockInjectionTests` covers the finalization window, the sync throttle and two dose dates;
/// this file covers the rest of the surface #377 touched.

// MARK: - The pure TandemCore constructors

/// `DoseEntry.bolus` and `UnfinalizedDose` take the date as a parameter rather than reading a
/// global, so a caller holding a clock can pass one. A default argument in Swift is re-evaluated at
/// every call, which is exactly what these tests pin: capturing one into a stored property would
/// make every later dose carry the first caller's timestamp.
@available(macOS 13.0, iOS 14.0, *) final class TandemCoreClockParameterTests: XCTestCase {
    private static let t0 = Date(timeIntervalSinceReferenceDate: 700_000_000)
    private static let step: TimeInterval = .minutes(37)
    private var t1: Date { Self.t0.addingTimeInterval(Self.step) }

    // MARK: DoseEntry.bolus(... now:)

    /// Without an explicit `endDate` the bolus runs `duration` from `now` — not from `startDate`,
    /// and not from whenever the module was first touched.
    func testBolusDoseEntryEndsDurationAfterTheSuppliedNow() {
        let dose = DoseEntry.bolus(
            units: 2.5,
            deliveredUnits: 0,
            duration: .minutes(3),
            activationType: .manualNoRecommendation,
            insulinType: .novolog,
            startDate: Self.t0,
            now: t1
        )

        XCTAssertEqual(dose.startDate, Self.t0)
        XCTAssertEqual(dose.endDate, t1.addingTimeInterval(.minutes(3)))
    }

    /// An explicit `endDate` wins over the clock entirely.
    func testBolusDoseEntryPrefersAnExplicitEndDateOverNow() {
        let explicitEnd = Self.t0.addingTimeInterval(.minutes(1))
        let dose = DoseEntry.bolus(
            units: 2.5,
            deliveredUnits: 2.5,
            duration: .minutes(3),
            activationType: .manualNoRecommendation,
            insulinType: .novolog,
            startDate: Self.t0,
            endDate: explicitEnd,
            now: t1
        )

        XCTAssertEqual(dose.endDate, explicitEnd)
    }

    /// The default argument still reads the wall clock, so production callers that pass nothing are
    /// unchanged. Two calls a moment apart must both see the current time, not one cached reading.
    func testBolusDoseEntryDefaultsToTheWallClockOnEveryCall() {
        let before = Date()
        let dose = DoseEntry.bolus(
            units: 1.0,
            deliveredUnits: 0,
            duration: 0,
            activationType: .manualNoRecommendation,
            insulinType: .novolog,
            startDate: Date(timeIntervalSinceReferenceDate: 0)
        )
        let after = Date()

        XCTAssertGreaterThanOrEqual(dose.endDate, before)
        XCTAssertLessThanOrEqual(dose.endDate, after.addingTimeInterval(1))
    }

    // MARK: UnfinalizedDose(bolus ... now:)

    func testUnfinalizedBolusIsDatedFromTheSuppliedNow() {
        let dose = UnfinalizedDose(
            units: 4.0,
            duration: .minutes(2),
            activationType: .manualNoRecommendation,
            insulinType: .novolog,
            bolusId: 11,
            now: t1
        )

        XCTAssertEqual(dose.startDate, t1)
        XCTAssertEqual(dose.estimatedEndDate, t1.addingTimeInterval(.minutes(2)))
    }

    func testUnfinalizedBolusDefaultsToTheWallClock() {
        let before = Date()
        let dose = UnfinalizedDose(
            units: 4.0,
            duration: 0,
            activationType: .manualNoRecommendation,
            insulinType: .novolog,
            bolusId: 11
        )

        XCTAssertGreaterThanOrEqual(dose.startDate, before)
        XCTAssertLessThanOrEqual(dose.startDate, Date().addingTimeInterval(1))
    }

    // MARK: UnfinalizedDose(tempRate ... startDate:)

    func testUnfinalizedTempBasalIsDatedFromTheSuppliedStartDate() {
        let dose = UnfinalizedDose(
            tempRate: 0.8,
            duration: .minutes(30),
            automatic: true,
            insulinType: .novolog,
            startDate: t1
        )

        XCTAssertEqual(dose.startDate, t1)
        XCTAssertEqual(dose.estimatedEndDate, t1.addingTimeInterval(.minutes(30)))
    }

    func testUnfinalizedTempBasalDefaultsToTheWallClock() {
        let before = Date()
        let dose = UnfinalizedDose(tempRate: 0.8, duration: 0, automatic: true, insulinType: .novolog)

        XCTAssertGreaterThanOrEqual(dose.startDate, before)
        XCTAssertLessThanOrEqual(dose.startDate, Date().addingTimeInterval(1))
    }

    // MARK: UnfinalizedDose.toDoseEntry(... now:)

    /// A bolus still estimated to be running cannot be reported as ending in the future, and "the
    /// future" is measured against the `now` handed in at call time.
    func testToDoseEntryClampsAnEstimatedEndDateToTheSuppliedNow() {
        let dose = UnfinalizedDose(
            units: 4.0,
            duration: .minutes(60),
            activationType: .manualNoRecommendation,
            insulinType: .novolog,
            bolusId: 11,
            now: Self.t0
        )

        let entry = dose.toDoseEntry(useEstimatedEndDate: true, now: t1)

        XCTAssertEqual(entry.endDate, t1, "The estimate runs past t1, so it is clamped to t1")
    }

    func testToDoseEntryKeepsAnEstimatedEndDateAlreadyInThePast() {
        let dose = UnfinalizedDose(
            units: 4.0,
            duration: .minutes(5),
            activationType: .manualNoRecommendation,
            insulinType: .novolog,
            bolusId: 11,
            now: Self.t0
        )

        let entry = dose.toDoseEntry(useEstimatedEndDate: true, now: t1)

        XCTAssertEqual(entry.endDate, Self.t0.addingTimeInterval(.minutes(5)))
    }

    /// With neither an explicit `endDate` nor the estimate, the entry ends at `now`.
    func testToDoseEntryEndsAtTheSuppliedNowWhenNoEndDateIsGiven() {
        let dose = UnfinalizedDose(
            units: 4.0,
            duration: .minutes(5),
            activationType: .manualNoRecommendation,
            insulinType: .novolog,
            bolusId: 11,
            now: Self.t0
        )

        XCTAssertEqual(dose.toDoseEntry(now: t1).endDate, t1)
    }

    func testToDoseEntryDefaultsToTheWallClock() {
        let dose = UnfinalizedDose(
            units: 4.0,
            duration: .minutes(5),
            activationType: .manualNoRecommendation,
            insulinType: .novolog,
            bolusId: 11
        )

        let before = Date()
        let entry = dose.toDoseEntry()

        XCTAssertGreaterThanOrEqual(entry.endDate, before)
        XCTAssertLessThanOrEqual(entry.endDate, Date().addingTimeInterval(1))
    }

    // MARK: UnfinalizedDose.defaultBasalDose(... now:)

    /// Both halves of this constructor read `now`: the dose's start date, and which segment of the
    /// basal schedule is in force. Moving the clock across a segment boundary must change the rate.
    func testDefaultBasalDoseReadsBothTheDateAndTheScheduleSegmentFromNow() throws {
        let schedule = try XCTUnwrap(BasalRateSchedule(dailyItems: [
            RepeatingScheduleValue(startTime: 0, value: 0.5),
            RepeatingScheduleValue(startTime: .hours(6), value: 1.5)
        ]))
        let startOfDay = Calendar.current.startOfDay(for: Self.t0)
        let earlyMorning = startOfDay.addingTimeInterval(.hours(1))
        let midMorning = startOfDay.addingTimeInterval(.hours(7))

        let early = UnfinalizedDose.defaultBasalDose(basalSchedule: schedule, insulineType: .novolog, now: earlyMorning)
        let later = UnfinalizedDose.defaultBasalDose(basalSchedule: schedule, insulineType: .novolog, now: midMorning)

        XCTAssertEqual(early.startDate, earlyMorning)
        XCTAssertEqual(early.value, 0.5)
        XCTAssertEqual(later.startDate, midMorning)
        XCTAssertEqual(later.value, 1.5, "The segment in force is the one containing `now`, not the one at construction")
    }

    /// `TandemPumpManagerState` builds its default basal dose before any manager (and therefore any
    /// clock) exists, so this one call keeps the wall-clock default.
    func testDefaultBasalDoseDefaultsToTheWallClock() throws {
        let schedule = try XCTUnwrap(BasalRateSchedule(dailyItems: [
            RepeatingScheduleValue(startTime: 0, value: 0.5)
        ]))

        let before = Date()
        let dose = UnfinalizedDose.defaultBasalDose(basalSchedule: schedule, insulineType: .novolog)

        XCTAssertGreaterThanOrEqual(dose.startDate, before)
        XCTAssertLessThanOrEqual(dose.startDate, Date().addingTimeInterval(1))
    }
}

// MARK: - The driver's time-gated decisions

@available(macOS 13.0, iOS 14.0, *) final class TandemClockGatedDecisionTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var clock: ManualClock!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!

    /// A clearly distinguishable interval: long enough that a T0 stamp can never be mistaken for a
    /// T1 one, short enough to stay inside the 4.5-minute-plus windows where a test needs it to.
    private static let step: TimeInterval = .minutes(37)
    private static let t0 = Date(timeIntervalSinceReferenceDate: 700_000_000)
    private static let pumpSerial: UInt32 = 123_456
    private static let bolusId = 4411
    private static let programmedUnits = 3.0

    /// The clock's reading after `advance()`.
    private var t1: Date { Self.t0.addingTimeInterval(Self.step) }

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        clock = ManualClock(Self.t0)
        manager = TandemPumpManager(
            state: Self.makeState(),
            bluetooth: bluetooth,
            clock: clock
        )
        delegate = MockPumpManagerDelegate()
        delegateQueue = DispatchQueue(label: "tandem-clock-gated-decision-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}
    }

    override func tearDown() {
        delegateQueue = nil
        delegate = nil
        manager = nil
        clock = nil
        bluetooth = nil
        super.tearDown()
    }

    private static func makeState() -> TandemPumpManagerState {
        let schedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!
        var state = TandemPumpManagerState(basalRateSchedule: schedule)
        state.hasSyncedBasalRateSchedule = true
        state.featureFlags[.historyBackfill] = true
        return state
    }

    // MARK: - Helpers

    /// Moves the clock to T1. Every test calls this *after* constructing the manager, so anything
    /// stamped T0 was read too early.
    private func advance(_ interval: TimeInterval = step) {
        clock.advance(by: interval)
    }

    private func settle() {
        delegateQueue.sync {}
    }

    private var reportedDoses: [DoseEntry] {
        settle()
        return delegate.pumpEvents.compactMap(\.dose)
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
        settle()
    }

    private func stubBolusStatus(statusId: Int, bolusId: Int, timestamp: UInt32 = 0) {
        bluetooth.stub(CurrentBolusStatusRequest.self, with: CurrentBolusStatusResponse(
            statusId: statusId,
            bolusId: bolusId,
            timestamp: timestamp,
            requestedVolume: UInt32(Self.programmedUnits * 1000),
            bolusSourceId: 0,
            bolusTypeBitmask: 0
        ))
    }

    /// The pump reports a basal icon on the home screen mirror; everything else is neutral.
    private func homeScreenMirror(basalIcon: HomeScreenMirrorResponse.BasalStatusIcon) -> HomeScreenMirrorResponse {
        HomeScreenMirrorResponse(
            cgmTrendIconId: 0,
            cgmAlertIconId: 0,
            statusIcon0Id: 0,
            statusIcon1Id: 0,
            bolusStatusIconId: 0,
            basalStatusIconId: basalIcon.rawValue,
            apControlStateIconId: 0,
            remainingInsulinPlusIcon: false,
            cgmDisplayData: false
        )
    }

    // MARK: - The manager's own clock

    /// Left alone, the manager runs on the wall clock: `#377` must not have changed the default.
    func testTheDefaultClockIsTheWallClock() {
        let systemManager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: StubPumpBluetooth())

        let before = Date()
        let now = systemManager.now

        XCTAssertGreaterThanOrEqual(now, before)
        XCTAssertLessThanOrEqual(now, Date().addingTimeInterval(1))
    }

    /// `now` is a computed read of the clock, not a value captured when the manager was built.
    func testManagerNowFollowsTheClockAfterConstruction() {
        XCTAssertEqual(manager.now, Self.t0)
        advance()
        XCTAssertEqual(manager.now, t1)
    }

    // MARK: - State-sync stamps (TandemPumpManager+StateSync)

    func testFetchTimeSinceResetStampsTheCheckAtTheClocksCurrentReading() {
        bluetooth.stub(TimeSinceResetRequest.self, with: TimeSinceResetResponse(
            currentTime: 500_000_000,
            pumpTimeSinceReset: 1000
        ))
        advance()

        manager.fetchTimeSinceReset()

        XCTAssertEqual(manager.state.lastPumpTimeCheckDate, t1)
    }

    func testFetchControlIQStatusStampsTheUpdateAtTheClocksCurrentReading() {
        manager.state.pumpState.apiVersion = KnownApiVersion.mobiApiV3_5.value
        bluetooth.stub(ControlIQInfoV2Request.self, with: ControlIQInfoV2Response(
            closedLoopEnabled: false,
            weight: 0,
            weightUnit: 0,
            totalDailyInsulin: 0,
            currentUserModeType: 0,
            byte6: 0,
            byte7: 0,
            byte8: 0,
            controlStateType: 0,
            exerciseChoice: 0,
            exerciseDuration: 0,
            exerciseTimeRemaining: 0
        ))
        advance()

        manager.fetchControlIQStatus()

        XCTAssertEqual(manager.state.lastControlIQUpdate, t1)
    }

    func testUpdateCGMSessionStateStampsTheUpdateAtTheClocksCurrentReading() {
        advance()

        manager.updateCGMSessionState(from: CGMStatusV2Response(
            sessionStateId: CGMStatusV2Response.SessionState.active.rawValue,
            lastCalibrationTimestamp: 0,
            sensorStartedTimestamp: 100,
            transmitterBatteryStatusId: CGMStatusV2Response.TransmitterBatteryStatus.unavailable.rawValue,
            sessionDurationSeconds: 3600,
            sessionTimeRemainingSeconds: 3600,
            cgmSensorTypeId: CGMStatusV2Response.CGMSensorType.dexcomG7.rawValue,
            gracePeriod: false
        ))

        XCTAssertEqual(manager.state.lastCGMStatusUpdate, t1)
    }

    func testFetchNotificationsStampsTheUpdateAtTheClocksCurrentReading() {
        // No stubs: an unanswering pump still ends the read, and the stamp is what is under test.
        advance()

        manager.fetchNotifications()

        XCTAssertEqual(manager.state.lastNotificationUpdate, t1)
    }

    func testFetchBatteryStatusDatesTheReadingByTheClock() throws {
        bluetooth.stub(CurrentBatteryV1Request.self, with: CurrentBatteryV1Response(
            currentBatteryAbc: 20,
            currentBatteryIbc: 80
        ))
        advance()

        manager.fetchBatteryStatus()

        XCTAssertEqual(try XCTUnwrap(manager.state.lastBatteryReading).date, t1)
    }

    func testFetchReservoirStatusDatesTheReadingAndTheReconciliationByTheClock() throws {
        bluetooth.stub(InsulinStatusRequest.self, with: InsulinStatusResponse(
            currentInsulinAmount: 150,
            isEstimate: 0,
            insulinLowAmount: 0
        ))
        advance()

        manager.fetchReservoirStatus()
        settle()

        XCTAssertEqual(try XCTUnwrap(manager.state.lastReservoirReading).startDate, t1)
        XCTAssertEqual(manager.state.lastReconciliation, t1)
        XCTAssertEqual(delegate.reservoirReadings.last?.date, t1)
    }

    func testFetchBasalStatusDatesASuspendDoseByTheClock() {
        bluetooth.stub(CurrentBasalStatusRequest.self, with: CurrentBasalStatusResponse(
            profileBasalRate: 1000,
            currentBasalRate: 0,
            basalModifiedBitmask: 0x01
        ))
        advance()

        manager.fetchBasalStatus()
        settle()

        XCTAssertEqual(manager.state.basalDose.type, .suspend)
        XCTAssertEqual(manager.state.basalDose.startDate, t1)
        XCTAssertEqual(manager.state.lastReconciliation, t1)
    }

    func testFetchBasalStatusDatesAResumedBasalDoseByTheClock() {
        manager.state.basalDose = UnfinalizedDose(suspendStartTime: Self.t0)
        bluetooth.stub(CurrentBasalStatusRequest.self, with: CurrentBasalStatusResponse(
            profileBasalRate: 1000,
            currentBasalRate: 1000,
            basalModifiedBitmask: 0x00
        ))
        advance()

        manager.fetchBasalStatus()
        settle()

        XCTAssertEqual(manager.state.basalDose.type, .basal)
        XCTAssertEqual(manager.state.basalDose.startDate, t1)
        XCTAssertEqual(manager.state.lastReconciliation, t1)
    }

    func testHomeScreenMirrorDatesASuspendDoseByTheClock() {
        advance()

        manager.handleHomeScreenMirrorResponse(homeScreenMirror(basalIcon: .suspend))
        settle()

        XCTAssertEqual(manager.state.basalDose.type, .suspend)
        XCTAssertEqual(manager.state.basalDose.startDate, t1)
    }

    func testHomeScreenMirrorDatesAResumeDoseByTheClock() {
        manager.state.basalDose = UnfinalizedDose(suspendStartTime: Self.t0)
        advance()

        manager.handleHomeScreenMirrorResponse(homeScreenMirror(basalIcon: .basal))
        settle()

        XCTAssertEqual(manager.state.basalDose.type, .resume)
        XCTAssertEqual(manager.state.basalDose.startDate, t1)
    }

    // MARK: - The 30-second bolus-sync grace

    /// Inside the grace period, event-driven tracking still owns the bolus.
    func testBolusSyncIsDeferredWhileTheClockIsInsideTheGracePeriod() {
        startBolus()
        let estimatedEnd = manager.state.bolusDose!.estimatedEndDate

        clock.set(estimatedEnd.addingTimeInterval(TandemPumpManager.bolusSyncReconcileGrace - 1))

        XCTAssertTrue(manager.shouldDeferBolusSync())
    }

    func testBolusSyncReconcilesOnceTheClockPassesTheGracePeriod() {
        startBolus()
        let estimatedEnd = manager.state.bolusDose!.estimatedEndDate

        clock.set(estimatedEnd.addingTimeInterval(TandemPumpManager.bolusSyncReconcileGrace + 1))

        XCTAssertFalse(manager.shouldDeferBolusSync())
    }

    /// The grace is measured from the clock when `shouldDeferBolusSync` runs, so waiting before the
    /// bolus is programmed does not pre-age it: a manager built long before the dose still defers.
    func testTheBolusSyncGraceIsNotPreAgedByAnOldManager() {
        advance(.hours(6))
        startBolus()

        XCTAssertTrue(
            manager.shouldDeferBolusSync(),
            "The grace runs from the dose's estimated end, read now — not from when the manager was built"
        )
    }

    /// `fetchBolusStatus(fromSync:)` consults the same gate, so a sync arriving inside the grace
    /// must not talk to the pump at all.
    func testSyncBolusFetchIsSkippedInsideTheGraceAndRunsOutsideIt() {
        startBolus()
        stubBolusStatus(statusId: 0, bolusId: 0)
        bluetooth.resetRecordedTraffic()

        manager.fetchBolusStatus(fromSync: true)
        XCTAssertFalse(bluetooth.didSend(CurrentBolusStatusRequest.self), "Inside the grace the sync stands down")

        clock.set(manager.state.bolusDose!.estimatedEndDate
            .addingTimeInterval(TandemPumpManager.bolusSyncReconcileGrace + 1))
        manager.fetchBolusStatus(fromSync: true)
        settle()

        XCTAssertTrue(bluetooth.didSend(CurrentBolusStatusRequest.self), "Past the grace the sync reconciles")
    }

    // MARK: - Bolus status handling

    /// The estimated end is recomputed from the clock at the moment the pump says delivery started,
    /// not from when the bolus was programmed.
    func testDeliveringBolusRecalculatesItsEstimatedEndFromTheClock() throws {
        startBolus()
        advance()
        stubBolusStatus(statusId: CurrentBolusStatusResponse.CurrentBolusStatus.delivering.rawValue, bolusId: Self.bolusId)

        manager.fetchBolusStatus(fromSync: false)
        settle()

        let dose = try XCTUnwrap(manager.state.bolusDose)
        XCTAssertEqual(
            dose.estimatedEndDate,
            t1.addingTimeInterval(manager.estimatedDuration(toBolus: Self.programmedUnits))
        )
    }

    func testAFinishedBolusStampsTheReconciliationFromTheClock() {
        startBolus()
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        advance()
        stubBolusStatus(statusId: 0, bolusId: 0)

        manager.fetchBolusStatus(fromSync: false)
        settle()

        XCTAssertEqual(manager.state.lastReconciliation, t1)
    }

    // MARK: - The 15-minute finalization window

    /// The window opens when the dose is held, and the hold reads the clock at hold time.
    func testHoldForFinalizationOpensTheWindowAtTheClocksCurrentReading() throws {
        startBolus()
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        advance()
        stubBolusStatus(statusId: 0, bolusId: 0)

        manager.fetchBolusStatus(fromSync: false)
        settle()

        XCTAssertEqual(try XCTUnwrap(manager.state.pendingBolusFinalization).estimatedEndDate, t1)
    }

    /// The window is 15 minutes from the hold, not 15 minutes from the manager being built: letting
    /// hours pass *before* the bolus must not finalize it early.
    func testTheFinalizationWindowIsNotPreAgedByAnOldManager() throws {
        advance(.hours(6))
        startBolus()
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        stubBolusStatus(statusId: 0, bolusId: 0)
        manager.fetchBolusStatus(fromSync: false)
        settle()
        XCTAssertEqual(manager.state.pendingBolusFinalization?.bolusId, Self.bolusId)

        clock.advance(by: TandemPumpManager.bolusFinalizationWindow - 1)
        manager.finalizePendingBolus()
        settle()

        XCTAssertEqual(
            manager.state.pendingBolusFinalization?.bolusId,
            Self.bolusId,
            "The window runs from the hold, so six hours of prior uptime must not consume it"
        )

        clock.advance(by: 2)
        manager.finalizePendingBolus()
        settle()

        XCTAssertNil(manager.state.pendingBolusFinalization, "One second past the window it finalizes")
    }

    /// Finalizing stamps the reconciliation and the dose's end from the clock at finalization time.
    func testFinalizingStampsTheReconciliationAndTheDoseEndFromTheClock() throws {
        startBolus()
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        stubBolusStatus(statusId: 0, bolusId: 0)
        manager.fetchBolusStatus(fromSync: false)
        settle()
        manager.state.pendingBolusFinalization?.deliveredUnits = Self.programmedUnits

        clock.advance(by: TandemPumpManager.bolusFinalizationWindow + 1)
        let finalizedAt = clock.now
        manager.finalizePendingBolus()
        settle()

        XCTAssertEqual(manager.state.lastReconciliation, finalizedAt)
        let finalized = try XCTUnwrap(reportedDoses.last { $0.type == .bolus })
        XCTAssertFalse(finalized.isMutable)
        XCTAssertLessThanOrEqual(finalized.endDate, finalizedAt, "The end is clamped to the clock, never past it")
    }

    // MARK: - The 4.5-minute sync throttle

    /// The throttle is measured from the clock at call time. A manager that has been up for hours
    /// and synced a moment ago is throttled; only the age of the sync matters.
    func testTheSyncThrottleIsNotPreAgedByAnOldManager() {
        advance(.hours(6))
        manager.state.lastReconciliation = clock.now
        clock.advance(by: .minutes(4))

        let done = expectation(description: "ensureCurrentPumpData")
        manager.ensureCurrentPumpData { _ in done.fulfill() }
        wait(for: [done], timeout: 5.0)

        XCTAssertEqual(bluetooth.ensureConnectedCount, 0, "Four minutes after a sync is still inside the throttle")
    }

    /// The 24-hour settings re-read runs off the same clock, and its stamp is taken at the moment
    /// the settings actually came back.
    func testTheSettingsReReadIsGatedAndStampedByTheClock() {
        bluetooth.stub(InsulinStatusRequest.self, with: InsulinStatusResponse(
            currentInsulinAmount: 150,
            isEstimate: 0,
            insulinLowAmount: 0
        ))
        // One answered settings read is what lets the sync stamp `lastSettingsCheckedAt` at all.
        bluetooth.stub(BasalLimitSettingsRequest.self, with: BasalLimitSettingsResponse(
            basalLimit: 3000,
            basalLimitDefault: 3000
        ))
        manager.state.lastSettingsCheckedAt = Self.t0
        clock.advance(by: .hours(23))

        let first = expectation(description: "sync inside 24h")
        manager.syncPumpData { _ in first.fulfill() }
        wait(for: [first], timeout: 10.0)
        settle()

        XCTAssertEqual(manager.state.lastSettingsCheckedAt, Self.t0, "Inside 24 hours the settings are not re-read")

        clock.advance(by: .hours(2))
        let checkedAt = clock.now
        let second = expectation(description: "sync past 24h")
        manager.syncPumpData { _ in second.fulfill() }
        wait(for: [second], timeout: 10.0)
        settle()

        XCTAssertEqual(manager.state.lastSettingsCheckedAt, checkedAt, "Past 24 hours it re-reads and stamps at the clock")
        XCTAssertEqual(manager.state.lastReconciliation, checkedAt)
    }

    // MARK: - Command paths

    /// A bolus programmed long after the manager was built carries the clock's reading, not T0.
    func testABolusProgrammedLaterIsDatedAtTheClocksCurrentReading() throws {
        advance()
        startBolus()

        let dose = try XCTUnwrap(manager.state.bolusDose)
        XCTAssertEqual(dose.startDate, t1)
        XCTAssertEqual(manager.state.lastReconciliation, t1)
        XCTAssertEqual(try XCTUnwrap(reportedDoses.last { $0.type == .bolus }).startDate, t1)
    }

    /// A cancel whose delivered volume the pump will not report stamps the reconciliation from the
    /// clock and opens the finalization window there too.
    func testCancellingABolusStampsTheReconciliationFromTheClock() throws {
        startBolus()
        bluetooth.stub(CancelBolusRequest.self, with: CancelBolusResponse(statusId: 0, bolusId: Self.bolusId, reasonId: 0))
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        advance()
        let cancelledAt = clock.now

        let done = expectation(description: "cancelBolus")
        manager.cancelBolus { _ in done.fulfill() }
        wait(for: [done], timeout: 20.0)
        settle()

        XCTAssertEqual(manager.state.lastReconciliation, cancelledAt)
        XCTAssertEqual(try XCTUnwrap(manager.state.pendingBolusFinalization).estimatedEndDate, cancelledAt)
    }

    func testATempBasalIsDatedAtTheClocksCurrentReading() throws {
        bluetooth.stub(CurrentBasalStatusRequest.self, with: CurrentBasalStatusResponse(
            profileBasalRate: 1000,
            currentBasalRate: 1000,
            basalModifiedBitmask: 0
        ))
        bluetooth.stub(SetTempRateRequest.self, with: SetTempRateResponse(status: 0, tempRateId: 42))
        bluetooth.stub(StopTempRateRequest.self, with: StopTempRateResponse(status: 0, tempRateId: 42))
        advance()

        let done = expectation(description: "enactTempBasal")
        manager.enactTempBasal(unitsPerHour: 0.5, for: .minutes(30)) { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        wait(for: [done], timeout: 10.0)
        settle()

        XCTAssertEqual(manager.state.basalDose.type, .tempBasal)
        XCTAssertEqual(manager.state.basalDose.startDate, t1)
        XCTAssertEqual(manager.state.basalDose.estimatedEndDate, t1.addingTimeInterval(.minutes(30)))
        XCTAssertEqual(manager.state.lastReconciliation, t1)
    }

    /// Cancelling a temp basal (a zero-length request) falls back to the scheduled basal, dated the
    /// same way.
    func testCancellingATempBasalDatesTheScheduledBasalByTheClock() {
        bluetooth.stub(CurrentBasalStatusRequest.self, with: CurrentBasalStatusResponse(
            profileBasalRate: 1000,
            currentBasalRate: 1000,
            basalModifiedBitmask: 0x02
        ))
        bluetooth.stub(StopTempRateRequest.self, with: StopTempRateResponse(status: 0, tempRateId: 42))
        advance()

        let done = expectation(description: "enactTempBasal cancel")
        manager.enactTempBasal(unitsPerHour: 0, for: 0) { _ in done.fulfill() }
        wait(for: [done], timeout: 10.0)
        settle()

        XCTAssertEqual(manager.state.basalDose.type, .basal)
        XCTAssertEqual(manager.state.basalDose.startDate, t1)
        XCTAssertEqual(manager.state.lastReconciliation, t1)
    }

    func testResumingDeliveryIsDatedAtTheClocksCurrentReading() throws {
        manager.state.basalDose = UnfinalizedDose(suspendStartTime: Self.t0)
        bluetooth.stub(ResumePumpingRequest.self, with: ResumePumpingResponse(status: 0))
        advance()

        let done = expectation(description: "resumeDelivery")
        manager.resumeDelivery { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        wait(for: [done], timeout: 10.0)
        settle()

        XCTAssertEqual(manager.state.basalDose.type, .resume)
        XCTAssertEqual(manager.state.basalDose.startDate, t1)
        XCTAssertEqual(manager.state.lastReconciliation, t1)
        XCTAssertEqual(try XCTUnwrap(reportedDoses.last { $0.type == .resume }).startDate, t1)
    }

    func testResumingDeliveryFinalizesATempBasalTheDriverStillHolds() throws {
        manager.state.basalDose = UnfinalizedDose(
            tempRate: 1.5,
            duration: .hours(1),
            automatic: false,
            insulinType: .novolog,
            startDate: Self.t0
        )
        bluetooth.stub(ResumePumpingRequest.self, with: ResumePumpingResponse(status: 0))
        advance()

        let done = expectation(description: "resumeDelivery")
        manager.resumeDelivery { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        wait(for: [done], timeout: 10.0)
        settle()

        let batch = try XCTUnwrap(delegate.pumpEventBatches.last)
        XCTAssertTrue(batch.replacePendingEvents)
        XCTAssertEqual(batch.events.compactMap(\.dose).map(\.type), [.tempBasal, .resume])

        let tempBasal = try XCTUnwrap(batch.events.compactMap(\.dose).first)
        XCTAssertFalse(tempBasal.isMutable)
        XCTAssertEqual(tempBasal.startDate, Self.t0)
        XCTAssertEqual(tempBasal.endDate, t1)
        XCTAssertEqual(tempBasal.deliveredUnits ?? -1, 1.5 * Self.step / .hours(1), accuracy: 0.000_001)
        XCTAssertEqual(manager.state.basalDose.type, .resume)
        XCTAssertEqual(manager.state.basalDose.startDate, t1)
    }

    func testRecordSiteChangeDefaultsToTheClock() {
        advance()

        manager.recordSiteChange(primeAmount: 0.3)
        settle()

        XCTAssertEqual(manager.state.lastSiteChangeDate, t1)
        XCTAssertEqual(manager.state.lastCannulaFillAmount, 0.3)
    }

    func testRecordSiteChangeStillHonoursAnExplicitDate() {
        advance()
        let explicit = Self.t0.addingTimeInterval(-.hours(3))

        manager.recordSiteChange(at: explicit)
        settle()

        XCTAssertEqual(manager.state.lastSiteChangeDate, explicit)
    }

    func testRecordCartridgeChangeDefaultsToTheClock() {
        advance()

        manager.recordCartridgeChange()
        settle()

        XCTAssertEqual(manager.state.lastCartridgeChangeDate, t1)
    }

    func testRecordCartridgeChangeStillHonoursAnExplicitDate() {
        advance()
        let explicit = Self.t0.addingTimeInterval(-.hours(3))

        manager.recordCartridgeChange(at: explicit)
        settle()

        XCTAssertEqual(manager.state.lastCartridgeChangeDate, explicit)
    }

    /// The time written to the pump is the clock's reading at the moment of the write.
    func testSyncPumpTimeWritesTheClocksCurrentReading() throws {
        bluetooth.stub(ChangeTimeDateRequest.self, with: ChangeTimeDateResponse(status: 0))
        advance()

        let done = expectation(description: "syncPumpTime")
        manager.syncPumpTime { result in
            guard case .success = result else {
                return XCTFail("syncPumpTime failed")
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 10.0)

        let request = try XCTUnwrap(bluetooth.sent(ChangeTimeDateRequest.self).last)
        XCTAssertEqual(request.tandemEpochTime, UInt32(Dates.fromInstantToJan12008EpochSeconds(t1)))
    }

    // MARK: - Derived reads

    /// A running temp basal superseded by a plain basal is closed off at the boundary its caller
    /// read from the clock — `getActivePumpEvents(endDate:)` is only ever given `now`.
    func testAnInterruptedTempBasalIsClosedAtTheClocksCurrentReading() throws {
        manager.state.basalDose = UnfinalizedDose(
            tempRate: 0.8,
            duration: .hours(3),
            automatic: true,
            insulinType: .novolog,
            startDate: Self.t0
        )
        bluetooth.stub(CurrentBasalStatusRequest.self, with: CurrentBasalStatusResponse(
            profileBasalRate: 1000,
            currentBasalRate: 1000,
            basalModifiedBitmask: 0x00
        ))
        advance()

        manager.fetchBasalStatus()
        settle()

        let tempBasal = try XCTUnwrap(reportedDoses.last { $0.type == .tempBasal })
        XCTAssertFalse(tempBasal.isMutable)
        XCTAssertEqual(tempBasal.endDate, t1, "The temp basal ends where the clock was when it was superseded")
        XCTAssertEqual(manager.state.basalDose.startDate, t1)
    }

    /// `getScheduledBasalRate` picks the segment containing the clock's reading, re-read per call.
    func testScheduledBasalRateFollowsTheClockAcrossASegmentBoundary() throws {
        let schedule = try XCTUnwrap(BasalRateSchedule(dailyItems: [
            RepeatingScheduleValue(startTime: 0, value: 0.5),
            RepeatingScheduleValue(startTime: .hours(6), value: 1.5)
        ]))
        manager.state.basalRateSchedule = schedule
        let startOfDay = Calendar.current.startOfDay(for: Self.t0)

        clock.set(startOfDay.addingTimeInterval(.hours(1)))
        XCTAssertEqual(manager.getScheduledBasalRate(), 0.5)

        clock.advance(by: .hours(6))
        XCTAssertEqual(manager.getScheduledBasalRate(), 1.5, "The segment is re-read every call, off the clock")
    }

    // MARK: - Connection staleness (PumpConnectionIssue)

    func testConnectionIsNotStaleWhileTheClockIsInsideTheThreshold() {
        bluetooth.bluetoothState = .poweredOn
        manager.state.isConnected = true
        manager.state.lastReconciliation = clock.now

        clock.advance(by: TandemPumpManager.connectionStaleThreshold - 60)

        XCTAssertNil(manager.connectionIssue)
    }

    func testConnectionGoesStaleOnceTheClockPassesTheThreshold() {
        bluetooth.bluetoothState = .poweredOn
        manager.state.isConnected = true
        manager.state.lastReconciliation = clock.now

        clock.advance(by: TandemPumpManager.connectionStaleThreshold + 60)

        XCTAssertEqual(manager.connectionIssue, .noRecentSync)
        XCTAssertEqual(manager.sustainedConnectionIssue, .noRecentSync)
    }

    /// The staleness threshold runs from the last sync as read now, so an old manager that synced a
    /// moment ago is healthy.
    func testConnectionStalenessIsNotPreAgedByAnOldManager() {
        bluetooth.bluetoothState = .poweredOn
        manager.state.isConnected = true
        advance(.hours(6))
        manager.state.lastReconciliation = clock.now

        XCTAssertNil(manager.connectionIssue)
    }

    /// A dropped link only reaches the home screen once it has cost loop cycles — the same
    /// threshold, off the same clock.
    func testASustainedDropIsReportedOnlyOncePastTheThreshold() {
        bluetooth.bluetoothState = .poweredOn
        manager.state.isConnected = false
        manager.state.lastReconciliation = clock.now

        clock.advance(by: TandemPumpManager.connectionStaleThreshold - 60)
        XCTAssertEqual(manager.connectionIssue, .pumpUnreachable)
        XCTAssertNil(manager.sustainedConnectionIssue, "A drop this young stays off the home screen")

        clock.advance(by: 120)
        XCTAssertEqual(manager.sustainedConnectionIssue, .pumpUnreachable)
    }

    // MARK: - History store (TandemPumpManager+HistoryStore)

    private func historyLog(sequenceNum: UInt32, at date: Date) -> BolusActivatedHistoryLog {
        BolusActivatedHistoryLog(
            pumpTimeSec: UInt32(Dates.fromInstantToJan12008EpochSeconds(date)),
            sequenceNum: sequenceNum,
            bolusId: Int(sequenceNum),
            selectedIob: 0,
            iob: 0,
            bolusSize: 1.0
        )
    }

    func testStoredHistoryLogsAreStampedWithTheClocksCurrentReading() throws {
        manager.state.pumpState.pumpSerial = Self.pumpSerial
        advance()

        manager.storeHistoryLogs([historyLog(sequenceNum: 1, at: clock.now)])

        let stored = try manager.historyLogStore.logs(pumpSerial: Self.pumpSerial, in: 1 ... 1)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.receivedAt, t1)
    }

    /// The prune interval is measured from the clock at call time on both sides of the boundary,
    /// and the watermark it writes is the clock's reading, not the manager's construction time.
    func testThePruneIntervalIsGatedAndStampedByTheClock() {
        manager.state.pumpState.pumpSerial = Self.pumpSerial
        advance()

        manager.pruneHistoryLogStoreIfNeeded()
        XCTAssertEqual(manager.lastHistoryLogPruneAt, t1, "The first prune stamps the clock's current reading")

        clock.advance(by: TandemPumpManager.historyLogPruneInterval - 60)
        manager.pruneHistoryLogStoreIfNeeded()
        XCTAssertEqual(manager.lastHistoryLogPruneAt, t1, "Inside the interval the prune is skipped")

        clock.advance(by: 120)
        let due = clock.now
        manager.pruneHistoryLogStoreIfNeeded()
        XCTAssertEqual(manager.lastHistoryLogPruneAt, due, "Past the interval it runs again and re-stamps")
    }

    /// Retention is applied relative to the clock: an entry inside the window survives a prune that
    /// the same entry would not survive once the clock has moved past its retention.
    func testRetentionIsAppliedRelativeToTheClock() throws {
        manager.state.pumpState.pumpSerial = Self.pumpSerial
        manager.storeHistoryLogs([historyLog(sequenceNum: 1, at: clock.now)])
        XCTAssertEqual(try manager.historyLogStore.count(pumpSerial: Self.pumpSerial), 1)

        clock.advance(by: HistoryLogRetention.default + .days(1))
        manager.pruneHistoryLogStoreIfNeeded()

        XCTAssertEqual(
            try manager.historyLogStore.count(pumpSerial: Self.pumpSerial),
            0,
            "Once the clock is past the retention window the entry is pruned"
        )
    }

    // MARK: - HistoryLogFetcher

    /// The fetcher stamps every streamed chunk with the manager's clock, which is what the export
    /// capture dates its records by.
    func testStreamedHistoryChunksAreStampedWithTheManagersClock() {
        manager.state.pumpState.pumpSerial = Self.pumpSerial
        let fetcher = HistoryLogFetcher(pumpManager: manager)
        defer { fetcher.cancel() }

        let stamped = expectation(description: "onStreamMessage")
        var receivedAt: Date?
        fetcher.onStreamMessage = { date, _ in
            receivedAt = date
            stamped.fulfill()
        }

        bluetooth.stub(HistoryLogStatusRequest.self, with: HistoryLogStatusResponse(
            numEntries: 1,
            firstSequenceNum: 1,
            lastSequenceNum: 1
        ))
        bluetooth.stub(HistoryLogRequest.self, with: HistoryLogResponse(status: 0, streamId: 7))
        bluetooth.onWrite = { [weak self] message in
            guard let self, message is HistoryLogRequest else { return }
            advance()
            manager.historyLogStream.send(HistoryLogStreamResponse(
                numberOfHistoryLogs: 1,
                streamId: 7,
                historyLogStreamBytes: [historyLog(sequenceNum: 1, at: Self.t0).cargo]
            ))
        }

        let finished = expectation(description: "fetch finishes")
        fetcher.start(numberOfLogs: 1) { _ in finished.fulfill() }
        wait(for: [stamped, finished], timeout: 60.0)

        XCTAssertEqual(receivedAt, t1, "The chunk is stamped when it arrives, off the manager's clock")
    }

    // MARK: - HistoryBackfillCoordinator

    /// `runTick` with no explicit date falls back to the manager's clock, which is what the tick's
    /// bookkeeping is dated by.
    func testBackfillTickDatesItsBookkeepingFromTheManagersClock() throws {
        manager.state.pumpState.pumpSerial = Self.pumpSerial
        let coordinator = HistoryBackfillCoordinator(pumpManager: manager)
        bluetooth.stub(HistoryLogStatusRequest.self, with: HistoryLogStatusResponse(
            numEntries: 1,
            firstSequenceNum: 1,
            lastSequenceNum: 1
        ))
        bluetooth.stub(HistoryLogRequest.self, with: HistoryLogResponse(status: 0, streamId: 7))
        bluetooth.onWrite = { [weak self] message in
            guard let self, message is HistoryLogRequest else { return }
            manager.historyLogStream.send(HistoryLogStreamResponse(
                numberOfHistoryLogs: 1,
                streamId: 7,
                historyLogStreamBytes: [historyLog(sequenceNum: 1, at: clock.now).cargo]
            ))
        }
        advance()

        let ticked = expectation(description: "runTick")
        coordinator.runTick { _ in ticked.fulfill() }
        wait(for: [ticked], timeout: 60.0)
        settle()

        let bookkeeping = try XCTUnwrap(manager.state.historyBackfill)
        XCTAssertEqual(
            try XCTUnwrap(bookkeeping.firstSeenFloor),
            t1.addingTimeInterval(-HistoryBackfillPlanner.deepFetchLookback),
            "The first-seen floor is one lookback back from the manager's clock, read when the tick ran"
        )
    }

    // MARK: - TandemDoseProgressReporter

    private func makeProgressReporter() -> TandemDoseProgressReporter {
        let dose = DoseEntry.bolus(
            units: Self.programmedUnits,
            deliveredUnits: 0,
            duration: .minutes(3),
            activationType: .manualNoRecommendation,
            insulinType: .novolog,
            startDate: Self.t0,
            now: Self.t0
        )
        return TandemDoseProgressReporter(
            pumpManager: manager,
            dose: dose,
            activationType: .manualNoRecommendation
        )
    }

    /// `detectedAt` defaults to the manager's clock, and it is the clamp on the reported end date.
    /// Detected 30 s in, the rate model's estimate for 3 U still runs past the clock, so the clamp
    /// bites and the reported end is exactly where the clock is now — not where it was when the
    /// reporter was constructed.
    func testProgressReporterPumpEventClampsToTheManagersClock() throws {
        let reporter = makeProgressReporter()
        clock.advance(by: 30)

        let event = reporter.getPumpEvent(actualDeliveredUnits: Self.programmedUnits)

        XCTAssertEqual(
            try XCTUnwrap(event.dose).endDate,
            Self.t0.addingTimeInterval(30),
            "With no pump timestamp the estimate runs past now, so it is clamped to the clock"
        )
    }

    /// The first `notify()` records the start off the clock; the second measures elapsed delivery
    /// against it. Neither may use a date captured when the reporter was constructed.
    func testProgressReporterMeasuresDeliveryAgainstTheClock() {
        let reporter = makeProgressReporter()
        advance()

        reporter.notify()
        XCTAssertEqual(reporter.bolusStatedOn, t1, "Delivery starts when notify() ran, not when the reporter was built")

        clock.advance(by: 60)
        reporter.notify()

        let expected = HistoryToDoseMapper.roundToReportingResolution(
            min(60 * TandemPumpCapabilities.bolusSpeedUnder10U, Self.programmedUnits)
        )
        XCTAssertEqual(reporter.progress.deliveredUnits, expected, accuracy: 1e-9)
    }
}
