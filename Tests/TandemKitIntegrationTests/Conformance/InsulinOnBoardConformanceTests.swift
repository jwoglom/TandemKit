import Foundation
import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

/// Group I (#354 P21-3): the pump's IOB against the boluses reported within the active profile's
/// insulin duration. faketandem shows bolus insulin alone with Control-IQ off, decaying linearly over
/// that duration, and adds basal above and below the profile with it on.
final class InsulinOnBoardConformanceTests: ConformanceTestCase {
    /// Delivery at the rate the driver's estimate assumes, as in the smoke test.
    private static let deliveryRate = 1.0 / TandemPumpCapabilities.estimatedBolusDuration(toDeliver: 1.0)
    /// The wire carries milliunits; the snapshot is not rounded.
    private static let readingAccuracy = 0.0006

    // MARK: - I1

    func testI1_thePumpsIOBIsReadUnderTheControlIQOpcodeWithControlIQOff() throws {
        let driver = try startWatchedDriver()
        XCTAssertEqual(driver.manager.state.controlIQEnabled, false, "the pump answered its Control-IQ read")
        XCTAssertEqual(driver.manager.state.pumpInsulinDuration?.current, .minutes(300), "the active profile's insulin duration")
        let mark = try logMark()

        try pumpBolus(2.0)
        _ = try sync()
        let synced = try pumpShows()
        XCTAssertEqual(synced.iobType, 0)
        XCTAssertEqual(synced.iob, 2.0, accuracy: 0.05)
        XCTAssertEqual(driver.manager.state.latestInsulinOnBoard ?? -1, synced.iob, accuracy: Self.readingAccuracy)

        try clock.advanceBoth(seconds: .minutes(10))
        let wornOff = try pumpShows().iob
        XCTAssertLessThan(wornOff, synced.iob)
        try harness.client.raiseQualifyingEvent(bitmask: QualifyingEvent.iobChange.id)
        try IntegrationWait.until("the iobChange event's read", timeout: 30) {
            abs((driver.manager.state.latestInsulinOnBoard ?? -1) - wornOff) < Self.readingAccuracy
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

        try clock.advanceBoth(seconds: UnreportedInsulinOnBoardMonitor.persistence)
        _ = try sync()

        XCTAssertEqual(driver.manager.state.latestInsulinOnBoard ?? -1, try pumpShows().iob, accuracy: Self.readingAccuracy)
        XCTAssertGreaterThan(driver.manager.state.latestInsulinOnBoard ?? 0, 1.5, "most of the bolus still on board")
        XCTAssertNil(flagged(driver))
    }

    // MARK: - I3

    func testI3_aBolusProgrammedOnThePumpIsFlaggedOnceItHasStayedAboveTheReportedBolusesAndClearsWhenItWearsOff() throws {
        let driver = try startWatchedDriver()
        try appBolus(1.0, driver)
        let batches = allPumpEventBatches.count
        try pumpBolus(3.0)

        _ = try sync()
        XCTAssertNil(flagged(driver), "not at first sight: a pump bolus reaches the host from history once it completes")

        try clock.advanceBoth(seconds: UnreportedInsulinOnBoardMonitor.persistence / 2)
        _ = try sync()
        XCTAssertNil(flagged(driver), "not before it has persisted")

        try clock.advanceBoth(seconds: UnreportedInsulinOnBoardMonitor.persistence / 2)
        _ = try sync()
        let shown = try pumpShows().iob
        XCTAssertEqual(try reportedUnits(driver) ?? -1, 1.0, accuracy: 0.0005)
        XCTAssertEqual(flagged(driver) ?? 0, shown - 1.0, accuracy: 0.001, "what the pump holds beyond the 1 U the app was told of")
        XCTAssertGreaterThan(shown - 1.0, 2.5, "most of the pump's 3 U")
        XCTAssertFalse(
            allPumpEventBatches.dropFirst(batches).flatMap(\.events).contains { $0.dose?.type == .bolus },
            "History Dose Reporting is off, so the host never hears of the pump's bolus"
        )

        try clock.advanceBoth(seconds: .minutes(210), ticks: 42)
        _ = try sync()
        XCTAssertLessThan(try pumpShows().iob, 1.0, "both boluses most of the way through the profile's five hours")
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
        // Reads the pump's IOB before history reports the bolus: an excess, not yet a persistent one.
        _ = try sync()
        _ = try IntegrationWait.value("the pump's bolus reported from its history", timeout: 120) {
            self.allPumpEventBatches.dropFirst(batches).flatMap(\.events)
                .first { $0.dose?.type == .bolus && $0.dose?.wasProgrammedByPumpUI == true }
        }
        XCTAssertEqual(try reportedUnits(driver) ?? -1, 3.0, accuracy: 0.0005)

        try clock.advanceBoth(seconds: UnreportedInsulinOnBoardMonitor.persistence)
        _ = try sync()
        XCTAssertGreaterThan(driver.manager.state.latestInsulinOnBoard ?? 0, 2.5, "most of the bolus still on board")
        XCTAssertNil(flagged(driver))
    }

    // MARK: - I5

    func testI5_aBolusOlderThanTheProfilesInsulinDurationDoesNotCount() throws {
        let driver = try startWatchedDriver(insulinDurationMinutes: 120)
        XCTAssertEqual(driver.manager.state.pumpInsulinDuration?.current, .hours(2))
        try appBolus(4.0, driver)

        try clock.advanceBoth(seconds: .minutes(150), ticks: 30)
        XCTAssertEqual(try pumpShows().iob, 0, accuracy: 0.0005, "the pump has stopped counting the app's 4 U too")
        try pumpBolus(2.0)
        _ = try sync()
        try clock.advanceBoth(seconds: UnreportedInsulinOnBoardMonitor.persistence)
        _ = try sync()

        XCTAssertEqual(try reportedUnits(driver) ?? -1, 0, accuracy: 0.0005, "the app's 4 U is past the profile's two hours")
        XCTAssertEqual(flagged(driver) ?? 0, try pumpShows().iob, accuracy: 0.001)
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

        _ = try sync()
        try clock.advanceBoth(seconds: UnreportedInsulinOnBoardMonitor.persistence)
        _ = try sync()

        let shown = try pumpShows()
        XCTAssertEqual(shown.iobType, 1, "Swan 6 h, which counts basal above and below the profile as well")
        let swan = try XCTUnwrap(shown.swanIob)
        XCTAssertGreaterThan(abs(swan - (shown.mudaliarIob ?? swan)), 0.01, "the two figures differ, so the reading says which was read")
        XCTAssertEqual(driver.manager.state.latestInsulinOnBoard ?? -1, swan, accuracy: Self.readingAccuracy, "the IOB the pump shows")
        XCTAssertNil(flagged(driver), "no bolus was reported, yet the pump's IOB is not held against them")
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
        _ = try sync()
        return driver
    }

    private func setProfileInsulinDuration(minutes: Int) throws {
        var profile = FaketandemIDPProfile.emulatorDefault
        profile.insulinDuration = minutes
        try harness.client.setIDPProfiles([profile])
    }

    private func pumpShows() throws -> FaketandemSnapshot.Insulin {
        try harness.client.snapshot().insulin
    }

    /// Enacted, delivered and finalized from `LastBolusStatus`.
    private func appBolus(_ units: Double, _ driver: FaketandemHarness.Driver) throws {
        XCTAssertNil(try enactBolus(units: units))
        let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        try advanceUntilBolusFinishes(bolusId: bolusId)
        try clock.advanceBoth(seconds: driver.manager.estimatedDuration(toBolus: units) + .minutes(2))
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
