import Foundation
import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

/// Group I (#354 P21-3): the pump's IOB against the boluses reported within the active profile's
/// insulin duration. faketandem's own IOB adds delivered basal and decays on a fixed four hours, so
/// each scenario sets what a pump with Control-IQ off would hold right before the read that takes it.
final class InsulinOnBoardConformanceTests: ConformanceTestCase {
    /// Delivery at the rate the driver's estimate assumes, as in the smoke test.
    private static let deliveryRate = 1.0 / TandemPumpCapabilities.estimatedBolusDuration(toDeliver: 1.0)

    override func setUpWithError() throws {
        try super.setUpWithError()
        // I7 wraps an emulator gap in XCTExpectFailure, which would otherwise end it there.
        continueAfterFailure = true
    }

    // MARK: - I1

    func testI1_thePumpsIOBIsReadUnderTheControlIQOpcodeWithControlIQOff() throws {
        let driver = try startWatchedDriver()
        XCTAssertEqual(driver.manager.state.controlIQEnabled, false, "the pump answered its Control-IQ read")
        XCTAssertEqual(driver.manager.state.pumpInsulinDuration?.current, .minutes(300), "the active profile's insulin duration")
        let mark = try logMark()

        try pumpHolds(1.25)
        _ = try sync()
        XCTAssertEqual(driver.manager.state.latestInsulinOnBoard ?? -1, 1.25, accuracy: 0.0005)

        try pumpHolds(0.75)
        try harness.client.raiseQualifyingEvent(bitmask: QualifyingEvent.iobChange.id)
        try IntegrationWait.until("the iobChange event's read", timeout: 30) {
            abs((driver.manager.state.latestInsulinOnBoard ?? -1) - 0.75) < 0.0005
        }

        let requests = try harness.requestsSeen(since: mark).map(\.message)
        XCTAssertEqual(requests.filter { $0 == "ControlIQIOBRequest" }.count, 2, "one for the sync, one for the event: \(requests)")
        XCTAssertFalse(requests.contains("NonControlIQIOBRequest"))
    }

    // MARK: - I2

    func testI2_anAppBolusTheHostWasToldOfIsNotFlagged() throws {
        let driver = try startWatchedDriver()
        try appBolus(2.0, driver)
        XCTAssertEqual(try reportedUnits(driver) ?? -1, 2.0, accuracy: 0.0005, "the bolus at its delivered amount")

        try pumpHolds(1.9)
        _ = try sync()
        try clock.advanceBoth(seconds: UnreportedInsulinOnBoardMonitor.persistence)
        try pumpHolds(1.7)
        _ = try sync()

        XCTAssertEqual(driver.manager.state.latestInsulinOnBoard ?? -1, 1.7, accuracy: 0.0005)
        XCTAssertNil(flagged(driver))
    }

    // MARK: - I3

    func testI3_aBolusProgrammedOnThePumpIsFlaggedOnceItHasStayedAboveTheReportedBolusesAndClearsWhenItWearsOff() throws {
        let driver = try startWatchedDriver()
        try appBolus(1.0, driver)
        let batches = allPumpEventBatches.count
        try pumpBolus(3.0)

        try pumpHolds(3.8)
        _ = try sync()
        XCTAssertNil(flagged(driver), "not at first sight: a pump bolus reaches the host from history once it completes")

        try clock.advanceBoth(seconds: UnreportedInsulinOnBoardMonitor.persistence / 2)
        try pumpHolds(3.6)
        _ = try sync()
        XCTAssertNil(flagged(driver), "not before it has persisted")

        try clock.advanceBoth(seconds: UnreportedInsulinOnBoardMonitor.persistence / 2)
        try pumpHolds(3.4)
        _ = try sync()
        XCTAssertEqual(flagged(driver) ?? 0, 2.4, accuracy: 0.001, "what the pump holds beyond the 1 U the app was told of")
        XCTAssertEqual(try reportedUnits(driver) ?? -1, 1.0, accuracy: 0.0005)
        XCTAssertFalse(
            allPumpEventBatches.dropFirst(batches).flatMap(\.events).contains { $0.dose?.type == .bolus },
            "History Dose Reporting is off, so the host never hears of the pump's bolus"
        )

        try clock.advanceBoth(seconds: .minutes(5))
        try pumpHolds(0.9)
        _ = try sync()
        XCTAssertNil(flagged(driver), "back within the 1 U reported")
    }

    // MARK: - I4

    func testI4_aBolusProgrammedOnThePumpAndReportedFromHistoryIsNotFlagged() throws {
        // The ledger starts hours back, so earlier scenarios' boluses would be reported from history too.
        try eraseHistory()
        let driver = try startWatchedDriver(historyDoseReporting: true)
        try IntegrationWait.until("the first backfill tick", timeout: 180) {
            driver.manager.state.historyBackfill != nil
        }
        let batches = allPumpEventBatches.count

        try pumpBolus(3.0)
        try clock.advanceBoth(seconds: 30, ticks: 3)
        // Read before history has reported the bolus: an excess, but not yet a persistent one.
        try pumpHolds(3.0)
        _ = try sync()
        _ = try IntegrationWait.value("the pump's bolus reported from its history", timeout: 120) {
            self.allPumpEventBatches.dropFirst(batches).flatMap(\.events)
                .first { $0.dose?.type == .bolus && $0.dose?.wasProgrammedByPumpUI == true }
        }
        XCTAssertEqual(try reportedUnits(driver) ?? -1, 3.0, accuracy: 0.0005)

        try clock.advanceBoth(seconds: UnreportedInsulinOnBoardMonitor.persistence)
        try pumpHolds(2.8)
        _ = try sync()
        XCTAssertNil(flagged(driver))
    }

    // MARK: - I5

    func testI5_aBolusOlderThanTheProfilesInsulinDurationDoesNotCount() throws {
        let driver = try startWatchedDriver(insulinDurationMinutes: 120)
        XCTAssertEqual(driver.manager.state.pumpInsulinDuration?.current, .hours(2))
        try appBolus(4.0, driver)

        try clock.advanceBoth(seconds: .minutes(150), ticks: 30)
        try pumpBolus(2.0)
        try pumpHolds(1.95)
        _ = try sync()
        try clock.advanceBoth(seconds: UnreportedInsulinOnBoardMonitor.persistence)
        try pumpHolds(1.8)
        _ = try sync()

        XCTAssertEqual(try reportedUnits(driver) ?? -1, 0, accuracy: 0.0005, "the app's 4 U is past the profile's two hours")
        XCTAssertEqual(flagged(driver) ?? 0, 1.8, accuracy: 0.001)
    }

    // MARK: - I6

    func testI6_aChangeToTheProfilesInsulinDurationIsReadOnItsProfileChangeEvent() throws {
        let driver = try startWatchedDriver()

        try setProfileInsulinDuration(minutes: 180)
        try harness.client.raiseQualifyingEvent(bitmask: QualifyingEvent.profileChange.id)
        try IntegrationWait.until("the shorter duration read", timeout: 30) {
            driver.manager.state.pumpInsulinDuration?.current == .minutes(180)
        }
        let shortened = try XCTUnwrap(driver.manager.state.pumpInsulinDuration)
        XCTAssertEqual(shortened.window(at: clock.now), .minutes(300), "a bolus given under five hours may still be on board")
        XCTAssertEqual(shortened.window(at: clock.now.addingTimeInterval(.minutes(300))), .minutes(180))

        try setProfileInsulinDuration(minutes: 360)
        try harness.client.raiseQualifyingEvent(bitmask: QualifyingEvent.profileChange.id)
        try IntegrationWait.until("the longer duration read", timeout: 30) {
            driver.manager.state.pumpInsulinDuration?.current == .minutes(360)
        }
        XCTAssertEqual(driver.manager.state.pumpInsulinDuration?.window(at: clock.now), .minutes(360))
    }

    // MARK: - I7

    func testI7_underControlIQNothingIsCompared() throws {
        let driver = try startWatchedDriver(closedLoop: true)
        XCTAssertEqual(driver.manager.state.controlIQEnabled, true)
        try pumpBolus(3.0)

        try pumpHolds(3.0)
        _ = try sync()
        try clock.advanceBoth(seconds: UnreportedInsulinOnBoardMonitor.persistence)
        try pumpHolds(2.9)
        _ = try sync()

        XCTAssertEqual(driver.manager.state.latestInsulinOnBoard ?? -1, 2.9, accuracy: 0.0005)
        XCTExpectFailure("faketandem answers ControlIQIOBRequest with iobType 0 (Mudaliar) under Control-IQ, where a pump answers 1 (Swan 6 h)") {
            XCTAssertNil(flagged(driver), "the pump's IOB counts basal above and below the profile as well")
        }
    }

    // MARK: - Helpers

    /// Paired and synced on a profile with `insulinDurationMinutes`, its ledger started before the
    /// window, so every bolus the pump still counts was either reported or not.
    private func startWatchedDriver(
        historyDoseReporting: Bool = false,
        insulinDurationMinutes: Int = 300,
        closedLoop: Bool = false
    ) throws -> FaketandemHarness.Driver {
        try setProfileInsulinDuration(minutes: insulinDurationMinutes)
        try harness.client.setState(["bolus_rate_units_per_second": Self.deliveryRate, "closed_loop_enabled": closedLoop])
        var state = TandemPumpManagerState(rawValue: [:])
        state.insulinType = .novolog
        state.featureFlags[.historyDoseReporting] = historyDoseReporting
        state.bolusReportLedger = BolusReportLedger(trackingSince: clock.now.addingTimeInterval(-.hours(9)))
        let driver = startDriver(state: state)
        try harness.pair(driver)
        try pumpHolds(0)
        _ = try sync()
        return driver
    }

    private func setProfileInsulinDuration(minutes: Int) throws {
        var profile = FaketandemIDPProfile.emulatorDefault
        profile.insulinDuration = minutes
        try harness.client.setIDPProfiles([profile])
    }

    private func pumpHolds(_ units: Double) throws {
        try harness.client.setState(["iob": units])
    }

    /// Enacted, delivered and finalized from `LastBolusStatus`; the pump then holds the whole bolus.
    private func appBolus(_ units: Double, _ driver: FaketandemHarness.Driver) throws {
        XCTAssertNil(try enactBolus(units: units))
        let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        try advanceUntilBolusFinishes(bolusId: bolusId)
        try clock.advanceBoth(seconds: driver.manager.estimatedDuration(toBolus: units) + .minutes(2))
        try pumpHolds(units)
        _ = try sync()
        try IntegrationWait.until("the app bolus finalized", timeout: 30) {
            driver.manager.state.bolusReportLedger.entries.contains { $0.bolusId == bolusId && $0.isFinalized }
        }
    }

    private func pumpBolus(_ units: Double) throws {
        try harness.client.startBolus(units: units, source: "pump")
        try advanceUntilBolusFinishes(bolusId: harness.client.snapshot().bolus.bolusId)
    }

    private func reportedUnits(_ driver: FaketandemHarness.Driver) throws -> Double? {
        let window = try XCTUnwrap(driver.manager.state.pumpInsulinDuration).window(at: clock.now)
        return driver.manager.state.bolusReportLedger.reportedUnits(since: clock.now.addingTimeInterval(-window))
    }

    private func flagged(_ driver: FaketandemHarness.Driver) -> Double? {
        driver.manager.unreportedInsulinOnBoard.flagged
    }

    private func logMark() throws -> Int {
        try harness.client.snapshot().requestLog.lastSeq
    }
}
