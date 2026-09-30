import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

/// A temp rate is a percent of the pump's own profile, so until the app's schedule has reached the
/// pump the driver must not set one (#443).
final class BasalScheduleSyncGateIntegrationTests: FaketandemIntegrationTestCase {
    /// The emulator's fixed profile: one segment at 0.85 U/hr from midnight.
    private static let pumpProfileRate = 0.85

    func testTempBasalIsRefusedUntilTheBasalScheduleHasSynced() throws {
        let driver = try pairedUnsyncedDriver(schedule: [(0, Self.pumpProfileRate)])

        try assertTempBasalRefused(driver)

        XCTAssertNoThrow(try syncBasalRateSchedule(driver, [(0, Self.pumpProfileRate)]).get())
        XCTAssertTrue(driver.manager.state.hasSyncedBasalRateSchedule)

        let logStart = try harness.client.snapshot().requestLog.lastSeq
        XCTAssertNil(try enactTempBasal(driver))
        XCTAssertTrue(
            try harness.requestsSeen(since: logStart).contains { $0.message == "SetTempRateRequest" },
            "a synced schedule lets the temp basal through"
        )
    }

    func testTempBasalStaysRefusedWhenSetupScheduleHasMoreEntriesThanThePumpHolds() throws {
        let hourly = (0 ..< 17).map { (TimeInterval($0) * .hours(1), Self.pumpProfileRate) }
        let driver = try pairedUnsyncedDriver(schedule: hourly)
        let logStart = try harness.client.snapshot().requestLog.lastSeq

        let failure = try applyOnboardingSettings(driver)
        XCTAssertEqual(failure?.basalSchedule as? BasalScheduleSyncError, .tooManyEntries(count: 17, maximum: 16))
        XCTAssertFalse(
            try harness.requestsSeen(since: logStart).contains { $0.message == "SetIDPSegmentRequest" },
            "an oversized schedule is refused before any segment write"
        )

        try assertTempBasalRefused(driver)

        // The host brings the schedule within the limit, as a user editing it after setup would.
        XCTAssertNoThrow(try syncBasalRateSchedule(driver, [(0, Self.pumpProfileRate)]).get())
        XCTAssertNil(try enactTempBasal(driver))
    }

    // MARK: - Helpers

    private func pairedUnsyncedDriver(schedule: [(TimeInterval, Double)]) throws -> FaketandemHarness.Driver {
        let basalRateSchedule = try XCTUnwrap(BasalRateSchedule(
            dailyItems: schedule.map { RepeatingScheduleValue(startTime: $0.0, value: $0.1) }
        ))
        let driver = makeDriver(
            state: TandemPumpManagerState(basalRateSchedule: basalRateSchedule),
            stageBasalScheduleSync: false
        )
        try harness.pair(driver)
        _ = try harness.sync(driver)
        XCTAssertFalse(driver.manager.state.hasSyncedBasalRateSchedule)
        return driver
    }

    private func assertTempBasalRefused(
        _ driver: FaketandemHarness.Driver,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let logStart = try harness.client.snapshot().requestLog.lastSeq

        let error = try enactTempBasal(driver)

        guard case let .configuration(underlying?) = error else {
            return XCTFail("expected a configuration error, got \(String(describing: error))", file: file, line: line)
        }
        XCTAssertEqual(
            underlying as? TandemPumpManagerValidationError,
            .basalScheduleNotSynced,
            file: file,
            line: line
        )
        let seen = try harness.requestsSeen(since: logStart).map(\.message)
        XCTAssertFalse(seen.contains("SetTempRateRequest"), "pump saw \(seen)", file: file, line: line)
        XCTAssertFalse(driver.delegate.pumpEvents.contains { $0.dose?.type == .tempBasal }, file: file, line: line)
    }

    private func enactTempBasal(_ driver: FaketandemHarness.Driver) throws -> PumpManagerError? {
        let box = ResultBox<PumpManagerError?>()
        driver.manager.enactTempBasal(unitsPerHour: Self.pumpProfileRate * 2, for: .minutes(30)) { box.set($0) }
        let error = try box.wait("enactTempBasal completion", timeout: 60)
        driver.drainDelegate()
        return error
    }

    private func syncBasalRateSchedule(
        _ driver: FaketandemHarness.Driver,
        _ schedule: [(TimeInterval, Double)]
    ) throws -> Result<BasalRateSchedule, Error> {
        let box = ResultBox<Result<BasalRateSchedule, Error>>()
        driver.manager.syncBasalRateSchedule(
            items: schedule.map { RepeatingScheduleValue(startTime: $0.0, value: $0.1) }
        ) { box.set($0) }
        return try box.wait("syncBasalRateSchedule completion", timeout: 90)
    }

    private func applyOnboardingSettings(_ driver: FaketandemHarness.Driver) throws -> OnboardingSettingsFailure? {
        let box = ResultBox<OnboardingSettingsFailure?>()
        driver.manager.applyOnboardingSettings { box.set($0) }
        return try box.wait("applyOnboardingSettings completion", timeout: 90)
    }
}
