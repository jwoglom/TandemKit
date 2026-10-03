import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

/// A temp rate is a percent of the pump's own profile, so none is set until the app's schedule has
/// reached the pump (#443). Each case stages the pump's profiles, syncs the host's schedule, and
/// checks the profile the pump ends up with and whether a temp basal goes out afterwards.
final class BasalScheduleSyncIntegrationTests: FaketandemIntegrationTestCase {
    private typealias Segment = FaketandemIDPProfile.Segment
    private typealias Schedule = [(hour: Double, rate: Double)]

    private static let twoSegmentProfile = FaketandemIDPProfile(
        id: 1,
        segments: [Segment(startTime: 0, basalRate: 800), Segment(startTime: 720, basalRate: 600)]
    )

    private static func hourly(_ count: Int) -> Schedule {
        (0 ..< count).map { (hour: Double($0), rate: 0.5 + Double($0) * 0.05) }
    }

    // MARK: - A pump holding no profile

    func testEmptyScheduleIsRejectedOnAPumpWithNoProfile() throws {
        try assertSyncRejected(pump: [], schedule: []) { error in
            guard case .configuration = error as? PumpManagerError else {
                return XCTFail("expected a configuration error, got \(error)")
            }
        }
    }

    func testOneEntryOnAPumpWithNoProfileCreatesTheProfile() throws {
        try assertSynced(pump: [], schedule: [(0, 0.9)], createsProfile: true)
    }

    func testTwoEntriesOnAPumpWithNoProfileCreateTheProfileAndASegment() throws {
        try assertSynced(pump: [], schedule: [(0, 0.9), (8, 0.6)], createsProfile: true)
    }

    func testSixteenEntriesOnAPumpWithNoProfileFillTheProfile() throws {
        try assertSynced(pump: [], schedule: Self.hourly(16), createsProfile: true)
    }

    func testSeventeenEntriesAreRejectedOnAPumpWithNoProfile() throws {
        try assertSyncRejected(pump: [], schedule: Self.hourly(17)) { error in
            XCTAssertEqual(error as? BasalScheduleSyncError, .tooManyEntries(count: 17, maximum: 16))
        }
    }

    // MARK: - A pump holding a two-segment profile

    func testOneEntryReplacesATwoSegmentProfile() throws {
        try assertSynced(pump: [Self.twoSegmentProfile], schedule: [(0, 1.0)], createsProfile: false)
    }

    func testTwoEntriesRewriteATwoSegmentProfile() throws {
        try assertSynced(pump: [Self.twoSegmentProfile], schedule: [(0, 1.0), (6, 0.7)], createsProfile: false)
    }

    func testThreeEntriesExtendATwoSegmentProfile() throws {
        try assertSynced(
            pump: [Self.twoSegmentProfile],
            schedule: [(0, 1.0), (6, 0.7), (18, 0.5)],
            createsProfile: false
        )
    }

    // MARK: - Setup

    func testTempBasalStaysRefusedWhenSetupScheduleHasMoreEntriesThanThePumpHolds() throws {
        let driver = try pairedUnsyncedDriver(pump: [.emulatorDefault], schedule: Self.hourly(17))
        let logStart = try harness.client.snapshot().requestLog.lastSeq

        let failure = try applyOnboardingSettings(driver)
        XCTAssertEqual(failure?.basalSchedule as? BasalScheduleSyncError, .tooManyEntries(count: 17, maximum: 16))
        try assertNoProfileWrites(since: logStart)
        XCTAssertEqual(try harness.client.snapshot().idpProfiles, [.emulatorDefault])

        try assertTempBasalRefused(driver)

        // The host brings the schedule within the limit, as a user editing it after setup would.
        XCTAssertNoThrow(try syncBasalRateSchedule(driver, [(0, 0.85)]).get())
        XCTAssertNil(try enactTempBasal(driver))
    }

    // MARK: - State saved before the sync flag existed

    func testTempBasalGoesOutWhenThePumpAlreadyHoldsTheSchedule() throws {
        let driver = try pairedUnsyncedDriver(pump: [Self.twoSegmentProfile], schedule: [(0, 0.8), (12, 0.6)])
        let logStart = try harness.client.snapshot().requestLog.lastSeq

        XCTAssertNil(try enactTempBasal(driver))

        let seen = try harness.requestsSeen(since: logStart).map(\.message)
        XCTAssertTrue(seen.contains("SetTempRateRequest"), "pump saw \(seen)")
        try assertNoProfileWrites(since: logStart)
        XCTAssertTrue(driver.manager.state.hasSyncedBasalRateSchedule)
    }

    func testTempBasalStaysRefusedWhenThePumpHoldsADifferentProfile() throws {
        let driver = try pairedUnsyncedDriver(pump: [Self.twoSegmentProfile], schedule: [(0, 0.8), (12, 0.65)])
        let logStart = try harness.client.snapshot().requestLog.lastSeq

        try assertTempBasalRefused(driver)

        try assertNoProfileWrites(since: logStart)
        XCTAssertEqual(try harness.client.snapshot().idpProfiles, [Self.twoSegmentProfile])
        XCTAssertFalse(driver.manager.state.hasSyncedBasalRateSchedule)
    }

    // MARK: - Cases

    private func assertSynced(
        pump: [FaketandemIDPProfile],
        schedule: Schedule,
        createsProfile: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let driver = try pairedUnsyncedDriver(pump: pump, schedule: schedule)
        try assertTempBasalRefused(driver, file: file, line: line)
        let logStart = try harness.client.snapshot().requestLog.lastSeq

        XCTAssertNoThrow(try syncBasalRateSchedule(driver, schedule).get(), file: file, line: line)

        let profiles = try XCTUnwrap(try harness.client.snapshot().idpProfiles, file: file, line: line)
        XCTAssertEqual(profiles.count, 1, "profiles on the pump: \(profiles)", file: file, line: line)
        XCTAssertEqual(
            profiles.first?.segments.map { [$0.startTime, $0.basalRate] },
            schedule.map { [Int(($0.hour * 60).rounded()), Int(($0.rate * 1000).rounded())] },
            "the pump's profile holds the host's schedule",
            file: file,
            line: line
        )
        let seen = try harness.requestsSeen(since: logStart).map(\.message)
        XCTAssertEqual(seen.contains("CreateIDPRequest"), createsProfile, "pump saw \(seen)", file: file, line: line)
        XCTAssertTrue(driver.manager.state.hasSyncedBasalRateSchedule, file: file, line: line)

        let tempStart = try harness.client.snapshot().requestLog.lastSeq
        XCTAssertNil(try enactTempBasal(driver), file: file, line: line)
        XCTAssertTrue(
            try harness.requestsSeen(since: tempStart).contains { $0.message == "SetTempRateRequest" },
            "a synced schedule lets the temp basal through",
            file: file,
            line: line
        )
    }

    private func assertSyncRejected(
        pump: [FaketandemIDPProfile],
        schedule: Schedule,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ checkError: (Error) -> Void
    ) throws {
        let driver = try pairedUnsyncedDriver(pump: pump, schedule: schedule)
        let logStart = try harness.client.snapshot().requestLog.lastSeq

        let result = try syncBasalRateSchedule(driver, schedule)

        guard case let .failure(error) = result else {
            return XCTFail("expected the sync to fail, got \(result)", file: file, line: line)
        }
        checkError(error)
        try assertNoProfileWrites(since: logStart, file: file, line: line)
        XCTAssertEqual(try harness.client.snapshot().idpProfiles, pump, file: file, line: line)
        XCTAssertFalse(driver.manager.state.hasSyncedBasalRateSchedule, file: file, line: line)
        try assertTempBasalRefused(driver, file: file, line: line)
    }

    // MARK: - Helpers

    private func pairedUnsyncedDriver(pump: [FaketandemIDPProfile], schedule: Schedule) throws -> FaketandemHarness.Driver {
        try harness.client.setIDPProfiles(pump)
        // An empty host schedule has no BasalRateSchedule; the driver's own copy is not what syncs.
        let items = (schedule.isEmpty ? [(hour: 0, rate: 0.85)] : schedule)
            .map { RepeatingScheduleValue(startTime: .hours($0.hour), value: $0.rate) }
        let driver = makeDriver(
            state: TandemPumpManagerState(basalRateSchedule: try XCTUnwrap(BasalRateSchedule(dailyItems: items))),
            stageBasalScheduleSync: false
        )
        try harness.pair(driver)
        _ = try harness.sync(driver)
        XCTAssertFalse(driver.manager.state.hasSyncedBasalRateSchedule)
        return driver
    }

    private func assertNoProfileWrites(since logStart: Int?, file: StaticString = #filePath, line: UInt = #line) throws {
        let seen = try harness.requestsSeen(since: logStart).map(\.message)
        XCTAssertFalse(
            seen.contains { $0 == "CreateIDPRequest" || $0 == "SetIDPSegmentRequest" },
            "a refused schedule writes nothing; pump saw \(seen)",
            file: file,
            line: line
        )
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
        let rate = driver.manager.getScheduledBasalRate() * 2
        let box = ResultBox<PumpManagerError?>()
        driver.manager.enactTempBasal(unitsPerHour: rate, for: .minutes(30)) { box.set($0) }
        let error = try box.wait("enactTempBasal completion", timeout: 60)
        driver.drainDelegate()
        return error
    }

    private func syncBasalRateSchedule(
        _ driver: FaketandemHarness.Driver,
        _ schedule: Schedule
    ) throws -> Result<BasalRateSchedule, Error> {
        let box = ResultBox<Result<BasalRateSchedule, Error>>()
        driver.manager.syncBasalRateSchedule(
            items: schedule.map { RepeatingScheduleValue(startTime: .hours($0.hour), value: $0.rate) }
        ) { box.set($0) }
        return try box.wait("syncBasalRateSchedule completion", timeout: 90)
    }

    private func applyOnboardingSettings(_ driver: FaketandemHarness.Driver) throws -> OnboardingSettingsFailure? {
        let box = ResultBox<OnboardingSettingsFailure?>()
        driver.manager.applyOnboardingSettings { box.set($0) }
        return try box.wait("applyOnboardingSettings completion", timeout: 90)
    }
}
