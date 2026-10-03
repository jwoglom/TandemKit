import Foundation
import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

/// The pump's basal rate against the app's schedule (AGENTS.md "Onboarding and the basal
/// schedule"): a rate the schedule doesn't have is flagged only once it outlasts
/// `basalMismatchConfirmationInterval`, a confirmed one stops temp basals until the rates agree, and a
/// schedule change that alters the rate in force stops a running temp basal instead of leaving the
/// pump to rescale it.
final class BasalScheduleChangeTests: ConformanceTestCase {
    private static let scheduledRate = 1.0
    /// Not on the schedule: what a profile edited on the pump's own screen leaves running.
    private static let pumpRate = 1.4

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = true
    }

    // MARK: - Staging

    @discardableResult
    private func stageDriver(historyBackfill: Bool = false) throws -> FaketandemHarness.Driver {
        try harness.client.setState(["basal_rate": Self.scheduledRate])
        var state = TandemPumpManagerState(basalRateSchedule: try XCTUnwrap(BasalRateSchedule(
            dailyItems: [RepeatingScheduleValue(startTime: 0, value: Self.scheduledRate)],
            timeZone: .current
        )))
        state.insulinType = .novolog
        state.featureFlags[.historyBackfill] = historyBackfill
        let driver = startDriver(state: state)
        try harness.pair(driver)
        _ = try sync()
        XCTAssertNil(driver.manager.state.basalRateMismatchSince, "the pump runs the schedule at the start")
        return driver
    }

    private func pumpRunsARateOffTheSchedule() throws {
        try harness.client.setState(["basal_rate": Self.pumpRate])
    }

    private func pumpAnnounces(_ event: QualifyingEvent) throws {
        try harness.client.raiseQualifyingEvent(bitmask: event.id)
    }

    private func basalStatusReads(since mark: Int) throws -> Int {
        try harness.requestsSeen(since: mark).filter { $0.message == "CurrentBasalStatusRequest" }.count
    }

    private func logMark() throws -> Int {
        try harness.client.snapshot().requestLog.lastSeq
    }

    // MARK: - S1

    func testS1_aRateOffTheScheduleIsFlaggedOnlyOnceItOutlastsTheConfirmationInterval() throws {
        let driver = try stageDriver()
        try pumpRunsARateOffTheSchedule()

        _ = try sync()
        let since = try XCTUnwrap(driver.manager.state.basalRateMismatchSince, "the first sync that reads it notes the mismatch")
        XCTAssertFalse(driver.manager.state.basalRateMismatchConfirmed, "one reading is not enough")

        try clock.advanceBoth(seconds: TandemPumpManager.basalMismatchConfirmationInterval - .minutes(1), ticks: 3)
        _ = try sync()
        XCTAssertFalse(driver.manager.state.basalRateMismatchConfirmed, "still inside the confirmation interval")
        XCTAssertEqual(driver.manager.state.basalRateMismatchSince, since)

        try clock.advanceBoth(seconds: .minutes(2), ticks: 2)
        _ = try sync()
        XCTAssertTrue(driver.manager.state.basalRateMismatchConfirmed, "the mismatch outlasted the interval")

        try harness.client.setState(["basal_rate": Self.scheduledRate])
        _ = try sync()
        XCTAssertNil(driver.manager.state.basalRateMismatchSince)
        XCTAssertFalse(driver.manager.state.basalRateMismatchConfirmed, "cleared once the pump runs the schedule again")
    }

    func testS1_aRateOffTheScheduleIsNotFlaggedWhileThePumpIsSuspended() throws {
        let driver = try stageDriver()
        try pumpRunsARateOffTheSchedule()
        try harness.client.suspend()

        for _ in 0..<3 {
            _ = try sync()
            try clock.advanceBoth(seconds: TandemPumpManager.basalMismatchConfirmationInterval / 2, ticks: 2)
        }
        _ = try sync()

        XCTAssertEqual(driver.manager.state.basalDose.type, .suspend, "the driver follows the pump's suspend")
        XCTAssertNil(driver.manager.state.basalRateMismatchSince, "a suspended pump delivers no rate to compare")
        XCTAssertFalse(driver.manager.state.basalRateMismatchConfirmed)
    }

    func testS1_aRateOffTheScheduleIsNotFlaggedUnderControlIQ() throws {
        let driver = try stageDriver()
        try harness.client.setState(["closed_loop_enabled": true])
        try pumpAnnounces(.controlIQInfo)
        try IntegrationWait.until("the driver to follow the pump into Control-IQ", timeout: 30) {
            driver.manager.state.useControlIQ
        }
        try pumpRunsARateOffTheSchedule()

        for _ in 0..<3 {
            _ = try sync()
            try clock.advanceBoth(seconds: TandemPumpManager.basalMismatchConfirmationInterval / 2, ticks: 2)
        }
        _ = try sync()

        XCTAssertNil(driver.manager.state.basalRateMismatchSince, "Control-IQ sets the rate itself")
        XCTAssertFalse(driver.manager.state.basalRateMismatchConfirmed)
    }

    // MARK: - S2

    /// A temp basal is a percent of the profile rate, so a schedule change rescales a running one on
    /// the pump. The driver stops it, both hosts end it at the stop, and the scheduled basal starts
    /// at the new rate.
    func testS2_aScheduleChangeThatAltersTheRateInForceStopsTheRunningTempBasal() throws {
        let driver = try stageDriver(historyBackfill: true)
        let start = allPumpEventBatches.count
        let tempRate = Self.scheduledRate * 2
        let newRate = 1.5
        let ranFor = TimeInterval.minutes(10)

        XCTAssertNil(try enactTempBasal(unitsPerHour: tempRate, duration: .minutes(60)))
        let tempStart = clock.now
        try clock.advanceBoth(seconds: ranFor, ticks: 10)
        let mark = try logMark()
        let changeAt = clock.now

        let box = ResultBox<Result<BasalRateSchedule, Error>>()
        driver.manager.syncBasalRateSchedule(items: [RepeatingScheduleValue(startTime: 0, value: newRate)]) { box.set($0) }
        if case let .failure(error) = try box.wait("syncBasalRateSchedule", timeout: syncTimeout) {
            return XCTFail("the schedule sync failed: \(error)")
        }
        drainDelegate()

        let sent = try harness.requestsSeen(since: mark).map(\.message)
        let profileWrite = sent.lastIndex { $0 == "SetIDPSegmentRequest" }
        let stop = sent.firstIndex(of: "StopTempRateRequest")
        XCTAssertNotNil(stop, "the driver stopped the temp basal: \(sent)")
        if let profileWrite, let stop {
            XCTAssertLessThan(profileWrite, stop, "after the profile write that rescaled it: \(sent)")
        }
        let pump = try harness.client.snapshot().basal
        XCTAssertFalse(pump.tempActive, "the pump runs no temp basal")
        XCTAssertEqual(pump.profileRate, newRate, accuracy: 0.001, "the pump runs the new schedule")

        XCTAssertEqual(driver.manager.state.basalDose.type, .basal)
        XCTAssertEqual(driver.manager.state.basalDose.value, newRate, accuracy: 0.001, "the scheduled basal restarts at the new rate")

        let finalized = try XCTUnwrap(
            allPumpEventBatches.dropFirst(start).flatMap(\.events).last { $0.dose?.type == .tempBasal && $0.dose?.isMutable == false },
            "the temp basal was finalized"
        )
        XCTAssertEqual(try XCTUnwrap(finalized.dose?.endDate).timeIntervalSince(changeAt), 0, accuracy: 2, "ended at the stop")
        XCTAssertEqual(finalized.dose?.deliveredUnits ?? -1, tempRate * ranFor / .hours(1), accuracy: 0.01)

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates("schedule change")
        trio.assertNoDuplicates("schedule change")
        XCTAssertEqual(loop.doses.filter { $0.dose.type == .tempBasal }.count, 1, "\(loop.doses.map(LoopDoseStoreOracle.describe))")
        XCTExpectFailure(
            "jwoglom/TandemKit#329: Trio skips a temp basal carrying deliveredUnits and ignores .basal, so ending a temp basal without a replacement never truncates its stored temp basal (true of the oracle's older Trio; #454)",
            strict: true
        ) {
            let truncating = trio.tempBasals.contains { row in
                row.timestamp == tempStart && row.tempBasalDurationMinutes == Int(ranFor / 60)
            } || trio.tempBasals.contains { $0.timestamp >= changeAt.addingTimeInterval(-1) }
            XCTAssertTrue(truncating, "Trio holds no truncating record; its temp basals are \(trio.tempBasals)")
        }

        let timeline = try timeline()
        let pumpTemp = try XCTUnwrap(timeline.tempRates.last, "timeline \(timeline)")
        XCTAssertTrue(pumpTemp.isFinished, "the pump recorded the stop: \(timeline)")
        timeline.assertMatches(loop, "schedule change")

        _ = try sync()
        XCTAssertNil(driver.manager.state.basalRateMismatchSince, "the pump's rate matches the new schedule")
    }

    // MARK: - S3

    /// The pump announces a profile change: the driver reads the basal status then, so a profile
    /// edited on the pump is checked without waiting for the host's next sync.
    func testS3_aProfileChangeEventRunsTheMismatchCheckWithoutASync() throws {
        let driver = try stageDriver()
        let mark = try logMark()
        try pumpRunsARateOffTheSchedule()

        try pumpAnnounces(.profileChange)
        try IntegrationWait.until("the driver to read the basal status on the event", timeout: 30) {
            driver.manager.state.basalRateMismatchSince != nil
        }
        XCTAssertGreaterThan(try basalStatusReads(since: mark), 0)
        XCTAssertFalse(driver.manager.state.basalRateMismatchConfirmed)

        try clock.advanceBoth(seconds: TandemPumpManager.basalMismatchConfirmationInterval + .minutes(1), ticks: 5)
        try pumpAnnounces(.activeProfileSegmentChange)
        try IntegrationWait.until("the second event to confirm the mismatch", timeout: 30) {
            driver.manager.state.basalRateMismatchConfirmed
        }
    }

    // MARK: - S4

    private func profile(rate: Double) -> FaketandemIDPProfile {
        FaketandemIDPProfile(id: 1, segments: [.init(startTime: 0, basalRate: Int((rate * 1000).rounded()))])
    }

    private func tempBasalsReported(since start: Int) -> [NewPumpEvent] {
        allPumpEventBatches.dropFirst(start).flatMap(\.events).filter { $0.dose?.type == .tempBasal }
    }

    private func assertTempBasalRefused(
        _ expected: TandemPumpManagerValidationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let start = allPumpEventBatches.count
        let mark = try logMark()

        let error = try enactTempBasal(unitsPerHour: Self.scheduledRate * 1.46, duration: .minutes(30))

        let underlying: Error?
        switch error {
        case let .deviceState(error?), let .configuration(error?): underlying = error
        default: underlying = nil
        }
        XCTAssertEqual(underlying as? TandemPumpManagerValidationError, expected, "got \(String(describing: error))", file: file, line: line)
        let sent = try harness.requestsSeen(since: mark).map(\.message)
        XCTAssertFalse(sent.contains("SetTempRateRequest"), "pump saw \(sent)", file: file, line: line)
        XCTAssertFalse(sent.contains("StopTempRateRequest"), "pump saw \(sent)", file: file, line: line)
        let reported = tempBasalsReported(since: start)
        XCTAssertTrue(reported.isEmpty, "no temp basal reaches the host: \(reported)", file: file, line: line)
    }

    /// The field report: a Mobi whose active profile reads 0 U/hr under a driver that holds the
    /// schedule as synced. Every temp rate is a percent of 0, so none goes out: first because the
    /// rate is 0, then because the confirmed mismatch unsyncs the schedule, until the host's schedule
    /// is written to the pump.
    func testS4_aZeroRateProfileRefusesTempBasalsUntilTheScheduleIsWrittenToThePump() throws {
        let driver = try stageDriver()
        try harness.client.setIDPProfiles([profile(rate: 0)])
        try harness.client.setState(["basal_rate": 0.0])

        try assertTempBasalRefused(.pumpProfileBasalRateIsZero)
        XCTAssertTrue(driver.manager.state.hasSyncedBasalRateSchedule, "one reading does not unsync the schedule")

        _ = try sync()
        try clock.advanceBoth(seconds: TandemPumpManager.basalMismatchConfirmationInterval + .minutes(1), ticks: 5)
        _ = try sync()
        XCTAssertTrue(driver.manager.state.basalRateMismatchConfirmed)
        XCTAssertFalse(driver.manager.state.hasSyncedBasalRateSchedule, "a confirmed mismatch unsyncs the schedule")
        try assertTempBasalRefused(.basalScheduleNotSynced)

        let box = ResultBox<Result<BasalRateSchedule, Error>>()
        driver.manager.syncBasalRateSchedule(items: [RepeatingScheduleValue(startTime: 0, value: Self.scheduledRate)]) { box.set($0) }
        if case let .failure(error) = try box.wait("syncBasalRateSchedule", timeout: syncTimeout) {
            return XCTFail("the schedule sync failed: \(error)")
        }
        XCTAssertEqual(try harness.client.snapshot().basal.profileRate, Self.scheduledRate, accuracy: 0.001)

        _ = try sync()
        XCTAssertFalse(driver.manager.state.basalRateMismatchConfirmed, "the pump runs the schedule again")
        let tempRate = Self.scheduledRate * 1.5
        XCTAssertNil(try enactTempBasal(unitsPerHour: tempRate, duration: .minutes(30)))
        let pump = try harness.client.snapshot().basal
        XCTAssertTrue(pump.tempActive)
        XCTAssertEqual(pump.tempRate, tempRate, accuracy: 0.001, "the pump delivers the rate the host was told")
    }

    // MARK: - S5

    /// A matching profile does not explain a live rate that differs, so it is not adopted while the
    /// mismatch stands; once the pump runs the schedule again, it is, and temp basals resume.
    func testS5_aConfirmedMismatchRefusesTempBasalsUntilThePumpRunsTheScheduleAgain() throws {
        let driver = try stageDriver()
        try harness.client.setIDPProfiles([profile(rate: Self.scheduledRate)])
        try pumpRunsARateOffTheSchedule()

        _ = try sync()
        try clock.advanceBoth(seconds: TandemPumpManager.basalMismatchConfirmationInterval + .minutes(1), ticks: 5)
        _ = try sync()
        XCTAssertTrue(driver.manager.state.basalRateMismatchConfirmed)
        XCTAssertFalse(driver.manager.state.hasSyncedBasalRateSchedule)
        try assertTempBasalRefused(.basalScheduleNotSynced)

        try harness.client.setState(["basal_rate": Self.scheduledRate])
        _ = try sync()
        XCTAssertFalse(driver.manager.state.basalRateMismatchConfirmed)

        XCTAssertNil(try enactTempBasal(unitsPerHour: Self.scheduledRate * 1.5, duration: .minutes(30)))
        XCTAssertTrue(driver.manager.state.hasSyncedBasalRateSchedule, "the matching profile was adopted")
        XCTAssertTrue(try harness.client.snapshot().basal.tempActive)
    }

    // MARK: - S6

    /// The pump's profile differs from the schedule before the mismatch is confirmed. The percent is
    /// worked out against the pump's own rate, so the temp runs at the rate the host is told.
    func testS6_aTempBasalOnAProfileThatDiffersRunsAtTheRequestedRate() throws {
        let driver = try stageDriver()
        try harness.client.setState(["basal_rate": 0.8])
        let start = allPumpEventBatches.count

        XCTAssertNil(try enactTempBasal(unitsPerHour: 1.5, duration: .minutes(30)))

        let pump = try harness.client.snapshot().basal
        XCTAssertTrue(pump.tempActive)
        XCTAssertEqual(pump.tempPercent, 188)
        let reported = try XCTUnwrap(tempBasalsReported(since: start).last?.dose)
        XCTAssertEqual(reported.unitsPerHour, pump.tempRate, accuracy: 0.01, "the host is told the rate the pump runs")
        XCTAssertEqual(driver.manager.state.basalDose.tempPercent, 188)
    }

    // MARK: - S7

    /// 0% of any profile is 0, so a zero temp goes out on a zero-rate profile, before any schedule sync.
    func testS7_aZeroTempGoesOutOnAZeroRateProfileBeforeAnySync() throws {
        let driver = try stageDriver()
        try harness.client.setIDPProfiles([profile(rate: 0)])
        try harness.client.setState(["basal_rate": 0.0])
        driver.manager.state.hasSyncedBasalRateSchedule = false

        XCTAssertNil(try enactTempBasal(unitsPerHour: 0, duration: .minutes(30)))

        let pump = try harness.client.snapshot().basal
        XCTAssertTrue(pump.tempActive)
        XCTAssertEqual(pump.tempPercent, 0)
        XCTAssertEqual(pump.tempRate, 0)
    }

    // MARK: - S8

    /// The pump's clock runs 11 minutes ahead, already in a 2.0 U/hr segment the phone reaches at
    /// 14:00. The host counts its own 1.0 meanwhile, so the pump runs 50 % until the phone catches
    /// up, and the user is alerted until the clock is synced.
    func testS8_aSkewedPumpClockRunsTheHostsScheduledRateAndAlertsUntilSynced() throws {
        let phoneStart = Calendar.current.startOfDay(for: Date()).addingTimeInterval(.hours(14) - .minutes(5))
        try clock.start(at: phoneStart, skewSeconds: 660)
        try harness.client.setState(["basal_rate": 2.0])
        var state = TandemPumpManagerState(basalRateSchedule: try XCTUnwrap(BasalRateSchedule(
            dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0), RepeatingScheduleValue(startTime: .hours(14), value: 2.0)],
            timeZone: .current
        )))
        state.insulinType = .novolog
        let driver = startDriver(state: state)
        try harness.pair(driver)
        _ = try sync()

        XCTAssertTrue(driver.manager.state.isPumpClockSkewed)
        let skewTemp = try harness.client.snapshot().basal
        XCTAssertTrue(skewTemp.tempActive, "the pump runs the host's 1.0 U/hr")
        XCTAssertEqual(skewTemp.tempPercent, 50)
        XCTAssertEqual(skewTemp.tempRate, 1.0, accuracy: 0.001)
        XCTAssertTrue(tempBasalsReported(since: 0).isEmpty, "the host counts its own scheduled rate")
        XCTAssertEqual(
            driver.delegate.issuedAlerts.map(\.identifier.alertIdentifier),
            [TandemPumpManager.pumpClockSkewAlertIdentifier]
        )

        try clock.advanceBoth(seconds: .minutes(6), ticks: 6)
        _ = try sync()
        XCTAssertFalse(try harness.client.snapshot().basal.tempActive, "the phone reached the pump's segment")

        let box = ResultBox<PumpManagerError?>()
        driver.manager.writePumpTime { box.set($0) }
        XCTAssertNil(try box.wait("writePumpTime", timeout: syncTimeout))
        _ = try sync()
        drainDelegate()
        XCTAssertFalse(driver.manager.state.isPumpClockSkewed)
        XCTAssertEqual(driver.delegate.retractedAlerts.map(\.alertIdentifier), [TandemPumpManager.pumpClockSkewAlertIdentifier])
    }
}
