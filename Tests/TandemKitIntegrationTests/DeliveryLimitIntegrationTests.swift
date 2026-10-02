import Foundation
import HealthKit
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
    private static let basalUnit = HKUnit.internationalUnit().unitDivided(by: .hour())

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = true
    }

    // MARK: - Helpers

    private func syncDeliveryLimits(maxBasal: Double, maxBolus: Double) throws -> Result<DeliveryLimits, Error> {
        let manager = try XCTUnwrap(current, "no driver").manager
        let limits = DeliveryLimits(
            maximumBasalRate: HKQuantity(unit: Self.basalUnit, doubleValue: maxBasal),
            maximumBolus: HKQuantity(unit: .internationalUnit(), doubleValue: maxBolus)
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
            driver.manager.state.maxBasalLimitMilliunits == 2000
        }
        XCTAssertEqual(driver.manager.state.maxBolusLimitMilliunits, 8000)
    }
}
