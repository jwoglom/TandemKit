import Foundation
import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

/// `applyOnboardingSettings` (AGENTS.md "Onboarding and the basal schedule") against a freshly
/// paired pump: what reaches the pump, in what order, what the pump holds afterwards, and which
/// refused writes fail setup.
final class OnboardingIntegrationTests: FaketandemIntegrationTestCase {
    private static let maxBasal = 3.0
    private static let maxBolus = 10.0
    private static let schedule: [(hour: Double, rate: Double)] = [(0, 0.8), (6, 1.2), (22, 0.9)]
    private static let sounds: [(field: String, value: PumpGlobalsResponse.AnnunciationEnum)] = [
        ("quickBolusAnnun", .vibrate),
        ("bolusAnnun", .audioLow),
        ("reminderAnnun", .audioMedium),
        ("alertAnnun", .audioHigh),
        ("alarmAnnun", .audioMedium),
    ]

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = true
    }

    // MARK: - Staging

    /// What the onboarding screens leave in the driver's state, on a pump that holds no profile
    /// and whose clock reads an hour fast; paired, not yet synced.
    private func pairedForOnboarding() throws -> FaketandemHarness.Driver {
        try harness.client.setIDPProfiles([])
        try harness.client.setPumpTimeOnThePump(deltaSeconds: .hours(1))
        var state = TandemPumpManagerState(basalRateSchedule: try XCTUnwrap(BasalRateSchedule(
            dailyItems: Self.schedule.map { RepeatingScheduleValue(startTime: .hours($0.hour), value: $0.rate) }
        )))
        state.settings.maxTempBasalRate = Self.maxBasal
        state.settings.maxBolus = Self.maxBolus
        state.quickBolusAnnun = .vibrate
        state.generalAnnun = .audioLow
        state.reminderAnnun = .audioMedium
        state.alertAnnun = .audioHigh
        state.alarmAnnun = .audioMedium
        state.pumpSoundsAwaitingWrite = true
        state.featureFlags[.quickBolusButtonSupport] = false
        // The pump's clock runs in real time here; a frozen driver clock set it behind by however
        // long pairing and the onboarding writes took.
        let driver = makeDriver(state: state, clock: SystemClock(), stageBasalScheduleSync: false)
        try harness.pair(driver)
        return driver
    }

    private func applyOnboardingSettings(_ driver: FaketandemHarness.Driver) throws -> OnboardingSettingsFailure? {
        let box = ResultBox<OnboardingSettingsFailure?>()
        driver.manager.applyOnboardingSettings { box.set($0) }
        return try box.wait("applyOnboardingSettings completion", timeout: 120)
    }

    private func refuse(_ message: String) throws {
        var fault = FaketandemFaultSpec(.errorResponse, message: message)
        fault.errorCode = 3
        XCTAssertNotNil(try harness.client.armFault(fault))
    }

    private func logMark() throws -> Int {
        try harness.client.snapshot().requestLog.lastSeq
    }

    /// The pump's clock against the phone's local time, in seconds.
    private func pumpClockError() throws -> TimeInterval {
        let clock = try harness.client.clock()
        let localSeconds = clock.now.timeIntervalSince1970 - FaketandemClock.tandemEpochUnix + TimeInterval(TimeZone.current.secondsFromGMT(for: clock.now))
        return TimeInterval(clock.pumpTimeSeconds) - localSeconds
    }

    private func assertPumpHoldsTheSchedule(file: StaticString = #filePath, line: UInt = #line) throws {
        let profile = try XCTUnwrap(try harness.client.snapshot().idpProfiles?.first, "the pump holds no profile", file: file, line: line)
        XCTAssertEqual(
            profile.segments.map { [$0.startTime, $0.basalRate] },
            Self.schedule.map { [Int($0.hour * 60), Int(($0.rate * 1000).rounded())] },
            file: file,
            line: line
        )
    }

    private func assertPumpHoldsTheSounds(file: StaticString = #filePath, line: UInt = #line) throws {
        let globals = try harness.client.settingsValue(for: "PumpGlobalsRequest")
        for sound in Self.sounds {
            XCTAssertEqual((globals[sound.field] as? NSNumber)?.intValue, sound.value.rawValue, sound.field, file: file, line: line)
        }
    }

    // MARK: - O1

    func testOnboardingWritesTheHostsSettingsToTheNewPumpInOrder() throws {
        let driver = try pairedForOnboarding()
        let mark = try logMark()

        XCTAssertNil(try applyOnboardingSettings(driver))

        let sent = try harness.requestsSeen(since: mark).map(\.message)
        let writes = ["SetMaxBasalLimitRequest", "SetMaxBolusLimitRequest", "CreateIDPRequest", "SetPumpSoundsRequest", "ChangeTimeDateRequest"]
        let positions = writes.map { name in sent.firstIndex(of: name) }
        XCTAssertFalse(positions.contains(nil), "every write reached the pump: \(sent)")
        XCTAssertEqual(positions.compactMap { $0 }, positions.compactMap { $0 }.sorted(), "limits, then basal, then sounds, then clock: \(sent)")

        let limits = try XCTUnwrap(try harness.client.snapshot().limits)
        XCTAssertEqual(limits.maxBasalMilliunits, 3000)
        XCTAssertEqual(limits.maxBolusMilliunits, 10000)
        try assertPumpHoldsTheSchedule()
        try assertPumpHoldsTheSounds()
        XCTAssertEqual(try pumpClockError(), 0, accuracy: 5, "the pump reads the phone's local time")
        driver.drainDelegate()
        XCTAssertEqual(driver.delegate.clockAdjustments.count, 1)
        XCTAssertEqual(driver.delegate.clockAdjustments.first ?? 0, -TimeInterval.hours(1), accuracy: 5, "moved back the hour it was fast")
        XCTAssertTrue(driver.manager.state.hasSyncedBasalRateSchedule)
        XCTAssertFalse(driver.manager.state.pumpSoundsAwaitingWrite)

        _ = try harness.sync(driver)
        XCTAssertFalse(driver.manager.state.showPumpTimeSyncWarning)
    }

    // MARK: - O2

    /// The pump refuses the profile: setup fails on the basal schedule, the rest is still written,
    /// and no temp basal is set against a profile the app never wrote (#443).
    func testARefusedBasalScheduleFailsSetup() throws {
        let driver = try pairedForOnboarding()
        try refuse("CreateIDPRequest")

        let failure = try XCTUnwrap(try applyOnboardingSettings(driver), "setup must fail")

        XCTAssertNotNil(failure.basalSchedule)
        XCTAssertNil(failure.deliveryLimits)
        XCTAssertEqual(try harness.client.snapshot().idpProfiles ?? [], [], "the pump holds no profile")
        XCTAssertFalse(driver.manager.state.hasSyncedBasalRateSchedule)
        try assertPumpHoldsTheSounds()
        XCTAssertEqual(try pumpClockError(), 0, accuracy: 5)

        let box = ResultBox<PumpManagerError?>()
        driver.manager.enactTempBasal(unitsPerHour: 1.5, for: .minutes(30)) { box.set($0) }
        guard case let .configuration(underlying?)? = try box.wait("enactTempBasal", timeout: 60) else {
            return XCTFail("a temp basal must be refused until the schedule is written")
        }
        XCTAssertEqual(underlying as? TandemPumpManagerValidationError, .basalScheduleNotSynced)
    }

    // MARK: - O3

    func testARefusedLimitWriteFailsSetup() throws {
        let driver = try pairedForOnboarding()
        try refuse("SetMaxBasalLimitRequest")

        let failure = try XCTUnwrap(try applyOnboardingSettings(driver), "setup must fail")

        XCTAssertNotNil(failure.deliveryLimits)
        let limits = try XCTUnwrap(try harness.client.snapshot().limits)
        XCTAssertEqual(limits.maxBasalMilliunits, FaketandemHarness.defaultMaxBasalMilliunits, "the pump kept its own max basal")
        XCTAssertEqual(limits.maxBolusMilliunits, FaketandemHarness.defaultMaxBolusMilliunits, "the bolus limit is not written after the basal one fails")
    }

    // MARK: - O4

    /// The pump refuses the clock write: setup still succeeds, and the time-sync warning shows the
    /// hour the pump is off by.
    func testARefusedClockWriteDoesNotFailSetup() throws {
        let driver = try pairedForOnboarding()
        try refuse("ChangeTimeDateRequest")

        XCTAssertNil(try applyOnboardingSettings(driver))

        XCTAssertEqual(try pumpClockError(), .hours(1), accuracy: 5, "the pump kept its own clock")
        driver.drainDelegate()
        XCTAssertEqual(driver.delegate.clockAdjustments, [])
        try assertPumpHoldsTheSchedule()
        _ = try harness.sync(driver)
        XCTAssertTrue(driver.manager.state.showPumpTimeSyncWarning)
    }

    // MARK: - O5

    /// The pump announces a settings change before the sounds are written. The pump-globals read it
    /// triggers must not replace the user's choices with what the pump still holds.
    func testSoundsChosenBeforePairingSurviveAPumpGlobalsReadBeforeTheyAreWritten() throws {
        let driver = try pairedForOnboarding()
        let mark = try logMark()
        try harness.client.raiseQualifyingEvent(bitmask: QualifyingEvent.globalPumpSettings.id)
        try IntegrationWait.until("the driver to read the pump's globals", timeout: 30) {
            try self.harness.requestsSeen(since: mark).contains { $0.message == "PumpGlobalsRequest" }
        }
        XCTAssertEqual(driver.manager.state.generalAnnun, .audioLow, "the user's choice, not the pump's")

        XCTAssertNil(try applyOnboardingSettings(driver))
        try assertPumpHoldsTheSounds()
    }

    // MARK: - O6

    func testOnboardingTurnsTheQuickBolusButtonOffBeforeTheFirstSync() throws {
        let driver = try pairedForOnboarding()
        XCTAssertEqual(try harness.client.quickBolusEnabled(), true, "faketandem's pump starts with the quick bolus button on")

        XCTAssertNil(try applyOnboardingSettings(driver))

        XCTAssertEqual(try harness.client.quickBolusEnabled(), false)
        XCTAssertEqual(driver.manager.state.quickBolusEnabled, false)
        try assertPumpHoldsTheSounds()
    }
}
