import Foundation
import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

/// The pump's delivery limits and the dosing commands the driver refuses (AGENTS.md "Therapy
/// command validation"): what reaches the pump, what the pump holds afterwards, and that a refused
/// command leaves no dose in either host.
final class DeliveryLimitIntegrationTests: ConformanceTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = true
    }

    // MARK: - Helpers

    private func syncDeliveryLimits(maxBasal: Double, maxBolus: Double) throws -> Result<DeliveryLimits, Error> {
        let manager = try XCTUnwrap(current, "no driver").manager
        let limits = DeliveryLimits(
            maximumBasalRate: LoopQuantity(unit: .internationalUnitsPerHour, doubleValue: maxBasal),
            maximumBolus: LoopQuantity(unit: .internationalUnit, doubleValue: maxBolus)
        )
        let box = ResultBox<Result<DeliveryLimits, Error>>()
        manager.syncDeliveryLimits(limits: limits) { box.set($0) }
        let result = try box.wait("syncDeliveryLimits completion", timeout: commandTimeout)
        drainDelegate()
        return result
    }

    private func requestsSince(_ mark: Int) throws -> [String] {
        try harness.requestsSeen(since: mark).map(\.message)
    }

    private func logMark() throws -> Int {
        try harness.client.snapshot().requestLog.lastSeq
    }

    private func eventsSince(_ count: Int) -> [NewPumpEvent] {
        Array(allPumpEventBatches.dropFirst(count)).flatMap(\.events)
    }

    private func validationError(_ error: PumpManagerError?) -> TandemPumpManagerValidationError? {
        guard case let .deviceState(underlying)? = error else { return nil }
        return underlying as? TandemPumpManagerValidationError
    }

    /// Paired and synced, with a one-rate schedule so a temp basal has a scheduled rate to scale.
    @discardableResult
    private func startDriverWithSchedule() throws -> FaketandemHarness.Driver {
        try harness.client.setState(["basal_rate": 1.0])
        var state = TandemPumpManagerState(rawValue: [:])
        state.basalRateSchedule = try XCTUnwrap(BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)]))
        let driver = startDriver(state: state)
        try harness.pair(driver)
        _ = try sync()
        return driver
    }

    /// The qualifying event the pump sends when its settings change; a sync reads them only daily.
    private func pumpAnnounces(_ event: QualifyingEvent) throws {
        try harness.client.raiseQualifyingEvent(bitmask: event.id)
    }

    private func pumpLimits() throws -> FaketandemSnapshot.Limits {
        try XCTUnwrap(try harness.client.snapshot().limits, "this emulator does not model delivery limits")
    }

    // MARK: - L1

    func testSyncedLimitsAreWrittenToThePumpAndReadBack() throws {
        let driver = try startPairedDriver()
        let mark = try logMark()

        XCTAssertNoThrow(try syncDeliveryLimits(maxBasal: 2.5, maxBolus: 8).get())

        let sent = try requestsSince(mark)
        XCTAssertTrue(sent.contains("SetMaxBasalLimitRequest"), "\(sent)")
        XCTAssertTrue(sent.contains("SetMaxBolusLimitRequest"), "\(sent)")
        let limits = try pumpLimits()
        XCTAssertEqual(limits.maxBolusMilliunits, 8000)
        XCTAssertEqual(limits.maxBasalMilliunits, 2500)
        XCTAssertEqual(driver.manager.state.settings.maxBolus, 8)
        XCTAssertEqual(driver.manager.state.settings.maxTempBasalRate, 2.5)

        try pumpAnnounces(.globalPumpSettings)
        try IntegrationWait.until("the driver to read the pump's limits", timeout: 30) {
            driver.manager.state.maxBolusLimitMilliunits == 8000
        }
        XCTAssertEqual(driver.manager.state.maxBasalLimitMilliunits, 2500, "read back from BasalLimitSettings")
    }

    // MARK: - L2

    func testBolusAboveTheSyncedMaxIsRefusedBeforeItReachesThePump() throws {
        try startPairedDriver()
        XCTAssertNoThrow(try syncDeliveryLimits(maxBasal: 2.5, maxBolus: 8).get())
        let mark = try logMark()
        let batchesBefore = allPumpEventBatches.count

        let error = try enactBolus(units: 9)

        XCTAssertEqual(validationError(error), .maximumBolusExceeded(requested: 9, maximum: 8), "\(String(describing: error))")
        let sent = try requestsSince(mark)
        XCTAssertFalse(sent.contains("BolusPermissionRequest") || sent.contains("InitiateBolusRequest"), "nothing reaches the pump: \(sent)")
        XCTAssertFalse(try harness.client.snapshot().bolus.active)
        XCTAssertTrue(eventsSince(batchesBefore).filter { $0.dose?.type == .bolus }.isEmpty, "\(eventsSince(batchesBefore))")

        XCTAssertNil(try enactBolus(units: 8), "the max itself is allowed")
        XCTAssertTrue(try harness.client.snapshot().bolus.active)
    }

    // MARK: - L3

    /// The driver has no limit of its own (never synced) and the pump's is lower than the bolus.
    /// The pump refuses it; the status a real pump refuses with is unconfirmed, the emulator
    /// answers `InitiateBolusResponse` status 1.
    func testABolusThePumpRefusesAboveItsOwnMaxIsNotReported() throws {
        let driver = try startPairedDriver()
        try harness.client.setState(["max_bolus_milliunits": 2000])
        XCTAssertNil(driver.manager.state.settings.maxBolus)
        let mark = try logMark()
        let batchesBefore = allPumpEventBatches.count

        let error = try enactBolus(units: 2.5)

        XCTAssertNotNil(error, "the pump's refusal fails the enact")
        XCTAssertTrue(try requestsSince(mark).contains("InitiateBolusRequest"))
        XCTAssertFalse(try harness.client.snapshot().bolus.active, "the pump started nothing")
        XCTAssertNil(driver.manager.state.bolusDose)
        XCTAssertTrue(eventsSince(batchesBefore).filter { $0.dose?.type == .bolus }.isEmpty, "\(eventsSince(batchesBefore))")
        let (loop, trio) = feedOracles()
        XCTAssertTrue(loop.doses.filter { $0.dose.type == .bolus }.isEmpty)
        XCTAssertTrue(trio.boluses.isEmpty)

        XCTAssertNil(try enactBolus(units: 1.5), "a bolus within the pump's max still goes through")
        XCTAssertTrue(try harness.client.snapshot().bolus.active)
    }

    // MARK: - L4

    func testTempBasalIsRefusedWhileAnAppBolusRuns() throws {
        let driver = try startDriverWithSchedule()
        try harness.client.setState(["bolus_rate_units_per_second": 0.02])
        XCTAssertNil(try enactBolus(units: 2))
        let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        try clock.advanceBoth(seconds: 10, ticks: 2)
        XCTAssertTrue(try harness.client.snapshot().bolus.active)
        let mark = try logMark()
        let batchesBefore = allPumpEventBatches.count

        let error = try enactTempBasal(unitsPerHour: 1.5, duration: .minutes(30))

        XCTAssertEqual(validationError(error), .bolusIsRunning, "\(String(describing: error))")
        XCTAssertFalse(try requestsSince(mark).contains("SetTempRateRequest"))
        XCTAssertFalse(try harness.client.snapshot().basal.tempActive)
        XCTAssertTrue(eventsSince(batchesBefore).filter { $0.dose?.type == .tempBasal }.isEmpty, "\(eventsSince(batchesBefore))")

        try advanceUntilBolusFinishes(bolusId: bolusId)
        try clock.advanceBoth(seconds: driver.manager.estimatedDuration(toBolus: 2) + .minutes(2))
        _ = try sync()
        XCTAssertNil(try enactTempBasal(unitsPerHour: 1.5, duration: .minutes(30)), "allowed once the bolus is done")
        XCTAssertTrue(try harness.client.snapshot().basal.tempActive)
    }

    // MARK: - L5

    /// Control-IQ turned on at the pump: the driver follows it and stops the host's automatic
    /// dosing, while a bolus the user asks for still goes through.
    func testControlIQOnThePumpBlocksAutomaticDosingButNotAManualBolus() throws {
        let driver = try startDriverWithSchedule()
        try harness.client.setState(["closed_loop_enabled": true])
        try pumpAnnounces(.controlIQInfo)
        try IntegrationWait.until("the driver to follow the pump into Control-IQ", timeout: 30) {
            driver.manager.state.useControlIQ
        }
        XCTAssertEqual(driver.manager.state.controlIQEnabled, true)
        let mark = try logMark()
        let batchesBefore = allPumpEventBatches.count

        XCTAssertEqual(validationError(try enactBolus(units: 0.5, activationType: .automatic)), .controlIQModeActive)
        XCTAssertEqual(validationError(try enactTempBasal(unitsPerHour: 1.5, duration: .minutes(30))), .controlIQModeActive)
        let sent = try requestsSince(mark)
        XCTAssertFalse(sent.contains("InitiateBolusRequest") || sent.contains("SetTempRateRequest"), "\(sent)")
        XCTAssertTrue(eventsSince(batchesBefore).isEmpty, "\(eventsSince(batchesBefore))")

        XCTAssertNil(try enactBolus(units: 0.5, activationType: .manualNoRecommendation))
        XCTAssertTrue(try harness.client.snapshot().bolus.active)
        XCTAssertNotNil(eventsSince(batchesBefore).first { $0.dose?.type == .bolus })
    }

    // MARK: - L6

    /// The pump takes the new max basal and refuses the new max bolus. The host is told the sync
    /// failed, and the driver keeps validating against the max bolus the pump still holds.
    func testABolusLimitThePumpRefusesLeavesTheDriverOnThePumpsLimit() throws {
        let driver = try startPairedDriver()
        XCTAssertNoThrow(try syncDeliveryLimits(maxBasal: 2.5, maxBolus: 8).get())
        var fault = FaketandemFaultSpec(.errorResponse, message: "SetMaxBolusLimitRequest")
        fault.errorCode = 3
        XCTAssertNotNil(try harness.client.armFault(fault))

        let result = try syncDeliveryLimits(maxBasal: 2.0, maxBolus: 5)

        guard case .failure = result else {
            return XCTFail("a refused limit write must fail the sync, got \(result)")
        }
        let limits = try pumpLimits()
        XCTAssertEqual(limits.maxBasalMilliunits, 2000, "the basal write went through")
        XCTAssertEqual(limits.maxBolusMilliunits, 8000, "the bolus write was refused")
        XCTAssertEqual(driver.manager.state.settings.maxBolus, 8, "the driver validates against the pump's max bolus")

        try pumpAnnounces(.globalPumpSettings)
        try IntegrationWait.until("the driver to read the pump's limits", timeout: 30) {
            driver.manager.state.maxBasalLimitMilliunits == 2000 && driver.manager.state.maxBolusLimitMilliunits == 8000
        }
    }

    // MARK: - L7

    /// The pump refuses a temp rate above 250% of its profile rate, so a max basal above that is cut
    /// to the ceiling: the pump runs it and the host is told the rate that runs.
    func testATempBasalAboveTheCeilingRunsAtTwoAndAHalfTimesTheProfileAndIsReportedSo() throws {
        try startDriverWithSchedule()
        XCTAssertNoThrow(try syncDeliveryLimits(maxBasal: 3.0, maxBolus: 8).get())
        let batchesBefore = allPumpEventBatches.count

        XCTAssertNil(try enactTempBasal(unitsPerHour: 3.0, duration: .minutes(30)))

        let basal = try harness.client.snapshot().basal
        XCTAssertTrue(basal.tempActive)
        XCTAssertEqual(basal.tempPercent, 250)
        XCTAssertEqual(basal.tempRate, 2.5, accuracy: 1e-9)
        let reported = eventsSince(batchesBefore).compactMap(\.dose).filter { $0.type == .tempBasal }
        XCTAssertEqual(reported.map(\.unitsPerHour), [2.5], "\(reported)")
        let (loop, trio) = feedOracles(trio: TrioDoseStoreOracle(maxBasal: 3.0))
        XCTAssertEqual(loop.doses.filter { $0.dose.type == .tempBasal }.map(\.dose.unitsPerHour), [2.5])
        XCTAssertEqual(trio.tempBasals.compactMap(\.tempBasalRate), [2.5])
    }

    /// pumpX2: the pump answers a SetTempRateRequest above 250% with an error.
    func testThePumpRefusesATempRateAboveTwoAndAHalfTimesItsProfile() throws {
        let driver = try startDriverWithSchedule()
        let box = ResultBox<SetTempRateResponse?>()
        driver.bluetooth.ensureConnected { _ in
            box.set(driver.bluetooth.write(SetTempRateRequest(minutes: 30, percent: 251)))
        }

        let response = try XCTUnwrap(try box.wait("SetTempRateRequest", timeout: commandTimeout))

        XCTAssertFalse(response.isStatusOK)
        XCTAssertFalse(try harness.client.snapshot().basal.tempActive)
    }

    // MARK: - L8

    /// A host's automatic bolus enacted while a manual one is still being initiated (#504).
    func testABolusEnactedWhileAnotherIsBeingInitiatedNeverReachesThePump() throws {
        let driver = try startPairedDriver()
        // Held so the automatic bolus is enacted while the manual one's command job runs.
        var hold = FaketandemFaultSpec(.delayResponse, message: "BolusPermissionRequest")
        hold.delayMilliseconds = Int(FaketandemHarness.responseTimeout * 1000 / 2)
        XCTAssertNotNil(try harness.client.armFault(hold))
        let mark = try logMark()
        let batchesBefore = allPumpEventBatches.count

        let manual = ResultBox<PumpManagerError?>()
        driver.manager.enactBolus(decisionId: nil, units: 1, activationType: .manualNoRecommendation) { manual.set($0) }
        try IntegrationWait.until("the pump to be asked to permit the manual bolus", timeout: 30) {
            try requestsSince(mark).contains("BolusPermissionRequest")
        }
        let automatic = ResultBox<PumpManagerError?>()
        driver.manager.enactBolus(decisionId: nil, units: 0.5, activationType: .automatic) { automatic.set($0) }

        XCTAssertNil(try manual.wait("manual enactBolus completion", timeout: commandTimeout))
        let error = try automatic.wait("automatic enactBolus completion", timeout: commandTimeout)
        drainDelegate()

        XCTAssertEqual(validationError(error), .bolusIsRunning, "\(String(describing: error))")
        let sent = try requestsSince(mark)
        XCTAssertEqual(sent.filter { $0 == "BolusPermissionRequest" }.count, 1, "\(sent)")
        XCTAssertEqual(sent.filter { $0 == "InitiateBolusRequest" }.count, 1, "\(sent)")
        let pumpBolus = try harness.client.snapshot().bolus
        XCTAssertTrue(pumpBolus.active)
        XCTAssertEqual(pumpBolus.unitsTotal, 1)
        XCTAssertEqual(pumpBolus.bolusId, driver.manager.state.bolusDose?.bolusId)
        let reported = eventsSince(batchesBefore).filter { $0.dose?.type == .bolus }
        XCTAssertEqual(Set(reported.map(\.raw)).count, 1, "\(reported)")
        XCTAssertEqual(Set(reported.compactMap(\.dose?.programmedUnits)), [1], "\(reported)")
        let (loop, trio) = feedOracles()
        XCTAssertEqual(loop.doses.filter { $0.dose.type == .bolus }.count, 1)
        XCTAssertEqual(trio.boluses.count, 1)
    }

    // MARK: - L9

    func testABolusIsRefusedWhileAnotherDeliversAndGoesOutOnceThatOneIsCancelled() throws {
        let driver = try startPairedDriver()
        XCTAssertNil(try enactBolus(units: 1))
        try clock.advanceBoth(seconds: 10, ticks: 2)
        XCTAssertTrue(try harness.client.snapshot().bolus.active)
        let mark = try logMark()

        let error = try enactBolus(units: 0.5, activationType: .automatic)

        XCTAssertEqual(validationError(error), .bolusIsRunning, "\(String(describing: error))")
        XCTAssertFalse(try requestsSince(mark).contains("BolusPermissionRequest"))

        guard case .success = try cancelBolus() else {
            return XCTFail("the pump must stop the first bolus")
        }
        XCTAssertFalse(try harness.client.snapshot().bolus.active)
        XCTAssertEqual(driver.manager.status.bolusState, .noBolus)

        XCTAssertNil(try enactBolus(units: 0.5, activationType: .automatic))
        let pumpBolus = try harness.client.snapshot().bolus
        XCTAssertTrue(pumpBolus.active)
        XCTAssertEqual(pumpBolus.unitsTotal, 0.5)
    }

    // MARK: - L10

    /// The app is not running while the pump finishes the bolus, so the relaunched driver still
    /// holds it as running.
    func testPastItsEstimatedEndABolusThatFinishedOutOfContactDoesNotHoldUpTheNext() throws {
        let driver = try startPairedDriver()
        let batchesBefore = allPumpEventBatches.count
        XCTAssertNil(try enactBolus(units: 1))
        let firstBolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        let firstRaw = try XCTUnwrap(eventsSince(batchesBefore).first { $0.dose?.type == .bolus }?.raw)
        let persisted = driver.manager.state.rawValue
        try shutDownDriver()
        try advanceUntilBolusFinishes(bolusId: firstBolusId)
        try clock.advanceBoth(seconds: driver.manager.estimatedDuration(toBolus: 1) + .minutes(2))
        let mark = try logMark()
        startDriver(state: TandemPumpManagerState(rawValue: persisted))

        XCTAssertNil(try enactBolus(units: 0.5, activationType: .automatic))

        let sent = try requestsSince(mark)
        let statusRead = try XCTUnwrap(sent.firstIndex(of: "CurrentBolusStatusRequest"), "\(sent)")
        let permission = try XCTUnwrap(sent.firstIndex(of: "BolusPermissionRequest"), "\(sent)")
        XCTAssertLessThan(statusRead, permission, "the pump is asked whether the first bolus finished: \(sent)")
        let snapshot = try harness.client.snapshot()
        XCTAssertTrue(snapshot.bolus.active)
        XCTAssertEqual(snapshot.bolus.unitsTotal, 0.5)
        XCTAssertEqual(snapshot.lastBolus?.bolusId, firstBolusId)
        let finalized = try syncUntilFinalized(raw: firstRaw)
        XCTAssertEqual(finalized.dose?.deliveredUnits, 1, "the first bolus still reaches the host")
    }

    // MARK: - L11

    func testPastItsEstimatedEndABolusThePumpStillDeliversHoldsUpTheNext() throws {
        let driver = try startPairedDriver()
        XCTAssertNil(try enactBolus(units: 1))
        try harness.client.stallBolus()
        try clock.advanceBoth(seconds: driver.manager.estimatedDuration(toBolus: 1) + .minutes(2))
        XCTAssertTrue(try harness.client.snapshot().bolus.active)
        let mark = try logMark()

        let error = try enactBolus(units: 0.5, activationType: .automatic)

        XCTAssertEqual(validationError(error), .bolusIsRunning, "\(String(describing: error))")
        let sent = try requestsSince(mark)
        XCTAssertTrue(sent.contains("CurrentBolusStatusRequest"), "\(sent)")
        XCTAssertFalse(sent.contains("BolusPermissionRequest"), "\(sent)")
    }

    // MARK: - L12

    func testPastItsEstimatedEndATempBasalIsRefusedWhileThePumpStillDeliversTheBolus() throws {
        let driver = try startDriverWithSchedule()
        let batchesBefore = allPumpEventBatches.count
        XCTAssertNil(try enactBolus(units: 1))
        let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        let bolusRaw = try XCTUnwrap(eventsSince(batchesBefore).first { $0.dose?.type == .bolus }?.raw)
        // The estimate counts from the first delivering status, so the clock waits for it.
        try IntegrationWait.until("the driver to see the bolus delivering", timeout: 30) {
            driver.manager.bolusProgressReport?.bolusStatedOn != nil
        }
        try harness.client.stallBolus()
        try clock.advanceBoth(seconds: driver.manager.estimatedDuration(toBolus: 1) + .minutes(2))
        try IntegrationWait.until("the driver's estimate to reach the programmed amount", timeout: 15) {
            driver.manager.bolusProgressReport?.isUnfinalized() == false
        }
        XCTAssertTrue(try harness.client.snapshot().bolus.active)
        let mark = try logMark()
        let refusedFrom = allPumpEventBatches.count

        let error = try enactTempBasal(unitsPerHour: 1.5, duration: .minutes(30))

        XCTAssertEqual(validationError(error), .bolusIsRunning, "\(String(describing: error))")
        let sent = try requestsSince(mark)
        XCTAssertTrue(sent.contains("CurrentBolusStatusRequest"), "\(sent)")
        XCTAssertFalse(sent.contains("SetTempRateRequest"), "\(sent)")
        XCTAssertFalse(try harness.client.snapshot().basal.tempActive)
        XCTAssertTrue(eventsSince(refusedFrom).isEmpty, "\(eventsSince(refusedFrom))")
        XCTAssertEqual(feedOracles().loop.mutableDoses.filter { $0.dose.type == .bolus }.count, 1)

        try harness.client.resumeBolus()
        let lastBolus = try advanceUntilBolusFinishes(bolusId: bolusId)
        try clock.advanceBoth(seconds: driver.manager.estimatedDuration(toBolus: 1) + .minutes(2))

        XCTAssertNil(try enactTempBasal(unitsPerHour: 1.5, duration: .minutes(30)), "allowed once the pump says the bolus finished")
        XCTAssertTrue(try harness.client.snapshot().basal.tempActive)
        let (loop, trio) = feedOracles()
        let stored = loop.assertPermanent(raw: bolusRaw, "once the pump has finished")
        XCTAssertEqual(stored?.dose.deliveredUnits ?? -1, lastBolus.deliveredUnits, accuracy: 0.0005)
        XCTAssertEqual(trio.boluses.count, 1)
    }

    // MARK: - L13

    /// No progress reporter survives a relaunch, so only the bolus the driver persisted holds the temp basal back.
    func testAfterARelaunchMidBolusATempBasalIsRefusedUntilThePumpSaysTheBolusFinished() throws {
        let driver = try startDriverWithSchedule()
        let batchesBefore = allPumpEventBatches.count
        XCTAssertNil(try enactBolus(units: 1))
        let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        let bolusRaw = try XCTUnwrap(eventsSince(batchesBefore).first { $0.dose?.type == .bolus }?.raw)
        try harness.client.stallBolus()
        let persisted = driver.manager.state.rawValue
        try shutDownDriver()
        let relaunched = startDriver(state: TandemPumpManagerState(rawValue: persisted))
        XCTAssertNil(relaunched.manager.bolusProgressReport)
        let mark = try logMark()

        let insideTheEstimate = try enactTempBasal(unitsPerHour: 1.5, duration: .minutes(30))
        try clock.advanceBoth(seconds: relaunched.manager.estimatedDuration(toBolus: 1) + .minutes(2))
        XCTAssertTrue(try harness.client.snapshot().bolus.active)
        let pastTheEstimate = try enactTempBasal(unitsPerHour: 1.5, duration: .minutes(30))

        XCTAssertEqual(validationError(insideTheEstimate), .bolusIsRunning, "\(String(describing: insideTheEstimate))")
        XCTAssertEqual(validationError(pastTheEstimate), .bolusIsRunning, "\(String(describing: pastTheEstimate))")
        let sent = try requestsSince(mark)
        XCTAssertTrue(sent.contains("CurrentBolusStatusRequest"), "\(sent)")
        XCTAssertFalse(sent.contains("SetTempRateRequest"), "\(sent)")
        XCTAssertFalse(try harness.client.snapshot().basal.tempActive)

        try harness.client.resumeBolus()
        let lastBolus = try advanceUntilBolusFinishes(bolusId: bolusId)
        try clock.advanceBoth(seconds: relaunched.manager.estimatedDuration(toBolus: 1) + .minutes(2))

        XCTAssertNil(try enactTempBasal(unitsPerHour: 1.5, duration: .minutes(30)), "allowed once the pump says the bolus finished")
        XCTAssertTrue(try harness.client.snapshot().basal.tempActive)
        let (loop, trio) = feedOracles()
        let stored = loop.assertPermanent(raw: bolusRaw, "once the pump has finished")
        XCTAssertEqual(stored?.dose.deliveredUnits ?? -1, lastBolus.deliveredUnits, accuracy: 0.0005)
        XCTAssertEqual(trio.boluses.count, 1)
    }
}
