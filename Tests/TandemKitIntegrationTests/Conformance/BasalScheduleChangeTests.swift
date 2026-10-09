import Foundation
import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

/// The pump's basal rate against the app's schedule (AGENTS.md "Onboarding and the basal
/// schedule"): a rate the schedule doesn't have starts an update that writes the schedule to the
/// pump, one still read after `basalProfileUpdateTimeout` fails it and stops temp basals until the
/// profile reads back matching, and a schedule change that alters the rate in force stops a running
/// temp basal instead of leaving the pump to rescale it.
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
        XCTAssertNil(driver.manager.state.basalRateMismatchDetectedAt, "the pump runs the schedule at the start")
        return driver
    }

    /// The update is queued behind the sync that started it, so it has not necessarily run when
    /// `sync()` returns.
    private func waitForUpdate(
        _ status: TandemPumpManagerState.BasalProfileUpdateStatus,
        _ driver: FaketandemHarness.Driver
    ) throws {
        try IntegrationWait.until("the basal profile update to be \(status)", timeout: 30) {
            driver.manager.state.basalProfileUpdateStatus == status
        }
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

    func testS1_aProfileOffTheScheduleIsWrittenOverOnTheFirstReading() throws {
        let driver = try stageDriver()
        try harness.client.setIDPProfiles([profile(rate: Self.pumpRate)])
        try pumpRunsARateOffTheSchedule()
        let mark = try logMark()

        _ = try sync()
        try waitForUpdate(.none, driver)

        XCTAssertTrue(try harness.requestsSeen(since: mark).contains { $0.message == "SetIDPSegmentRequest" })
        let pump = try harness.client.snapshot().basal
        XCTAssertEqual(pump.profileRate, Self.scheduledRate, accuracy: 0.001, "the pump runs the schedule")
        XCTAssertNil(driver.manager.state.basalRateMismatchDetectedAt)
        XCTAssertTrue(driver.manager.state.hasSyncedBasalRateSchedule)
    }

    /// The profile already matches, so the write changes nothing and the rate in force still differs.
    func testS1_aRateOffAMatchingProfileFailsTheUpdateOnceItOutlastsTheTimeout() throws {
        let driver = try stageDriver()
        try harness.client.setIDPProfiles([profile(rate: Self.scheduledRate)])
        try pumpRunsARateOffTheSchedule()

        _ = try sync()
        let detectedAt = try XCTUnwrap(driver.manager.state.basalRateMismatchDetectedAt, "the first sync that reads it notes the mismatch")
        XCTAssertEqual(driver.manager.state.basalProfileUpdateStatus, .updating)

        try clock.advanceBoth(seconds: TandemPumpManager.basalProfileUpdateTimeout - .minutes(1), ticks: 3)
        _ = try sync()
        XCTAssertEqual(driver.manager.state.basalProfileUpdateStatus, .updating, "still inside the timeout")
        XCTAssertEqual(driver.manager.state.basalRateMismatchDetectedAt, detectedAt)

        try clock.advanceBoth(seconds: .minutes(2), ticks: 2)
        _ = try sync()
        XCTAssertEqual(driver.manager.state.basalProfileUpdateStatus, .failed, "the mismatch outlasted the timeout")

        try harness.client.setState(["basal_rate": Self.scheduledRate])
        try clock.advanceBoth(seconds: TandemPumpManager.basalProfileUpdateRetryInterval, ticks: 1)
        _ = try sync()
        try waitForUpdate(.none, driver)
        XCTAssertNil(driver.manager.state.basalRateMismatchDetectedAt, "cleared once the profile reads back and the pump runs it")
    }

    func testS1_aRateOffTheScheduleIsNotFlaggedWhileThePumpIsSuspended() throws {
        let driver = try stageDriver()
        try pumpRunsARateOffTheSchedule()
        try harness.client.suspend()

        for _ in 0..<3 {
            _ = try sync()
            try clock.advanceBoth(seconds: TandemPumpManager.basalProfileUpdateTimeout / 2, ticks: 2)
        }
        _ = try sync()

        XCTAssertEqual(driver.manager.state.basalDose.type, .suspend, "the driver follows the pump's suspend")
        XCTAssertNil(driver.manager.state.basalRateMismatchDetectedAt, "a suspended pump delivers no rate to compare")
        XCTAssertEqual(driver.manager.state.basalProfileUpdateStatus, .none)
    }

    /// Control-IQ sets the rate it runs, but hands back to the pump's profile, which is what is
    /// checked against the schedule and written over.
    func testS1_aProfileOffTheScheduleIsWrittenOverUnderControlIQ() throws {
        let driver = try stageDriver()
        try harness.client.setState(["closed_loop_enabled": true])
        try pumpAnnounces(.controlIQInfo)
        try IntegrationWait.until("the driver to follow the pump into Control-IQ", timeout: 30) {
            driver.manager.state.useControlIQ
        }
        try harness.client.setIDPProfiles([profile(rate: Self.pumpRate)])
        try pumpRunsARateOffTheSchedule()
        let mark = try logMark()

        _ = try sync()
        try waitForUpdate(.none, driver)

        XCTAssertTrue(try harness.requestsSeen(since: mark).contains { $0.message == "SetIDPSegmentRequest" })
        XCTAssertEqual(try harness.client.snapshot().basal.profileRate, Self.scheduledRate, accuracy: 0.001, "the pump's profile is the schedule")
        XCTAssertNil(driver.manager.state.basalRateMismatchDetectedAt)
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
        let truncating = trio.tempBasals.contains { row in
            row.timestamp == tempStart && row.tempBasalDurationMinutes == Int(ranFor / 60)
        } || trio.tempBasals.contains { $0.timestamp >= changeAt.addingTimeInterval(-1) }
        XCTAssertTrue(truncating, "Trio holds no truncating record; its temp basals are \(trio.tempBasals)")

        let timeline = try timeline()
        let pumpTemp = try XCTUnwrap(timeline.tempRates.last, "timeline \(timeline)")
        XCTAssertTrue(pumpTemp.isFinished, "the pump recorded the stop: \(timeline)")
        timeline.assertMatches(loop, "schedule change")

        _ = try sync()
        XCTAssertNil(driver.manager.state.basalRateMismatchDetectedAt, "the pump's rate matches the new schedule")
    }

    // MARK: - S3

    /// The pump announces a profile change: the driver reads the basal status then, so a profile
    /// edited on the pump is checked without waiting for the host's next sync.
    func testS3_aProfileChangeEventRunsTheMismatchCheckWithoutASync() throws {
        let driver = try stageDriver()
        try harness.client.setIDPProfiles([profile(rate: Self.scheduledRate)])
        let mark = try logMark()
        try pumpRunsARateOffTheSchedule()

        try pumpAnnounces(.profileChange)
        try IntegrationWait.until("the driver to read the basal status on the event", timeout: 30) {
            driver.manager.state.basalRateMismatchDetectedAt != nil
        }
        XCTAssertGreaterThan(try basalStatusReads(since: mark), 0)
        XCTAssertNotEqual(driver.manager.state.basalProfileUpdateStatus, .failed)

        try clock.advanceBoth(seconds: TandemPumpManager.basalProfileUpdateTimeout + .minutes(1), ticks: 5)
        try pumpAnnounces(.activeProfileSegmentChange)
        try waitForUpdate(.failed, driver)
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
    /// schedule as synced. Every temp rate is a percent of 0, so none goes out until the next sync
    /// writes the host's schedule over the profile.
    func testS4_aZeroRateProfileRefusesTempBasalsUntilASyncWritesTheSchedule() throws {
        let driver = try stageDriver()
        try harness.client.setIDPProfiles([profile(rate: 0)])
        try harness.client.setState(["basal_rate": 0.0])

        try assertTempBasalRefused(.pumpProfileBasalRateIsZero)

        _ = try sync()
        try waitForUpdate(.none, driver)
        XCTAssertEqual(try harness.client.snapshot().basal.profileRate, Self.scheduledRate, accuracy: 0.001)
        XCTAssertTrue(driver.manager.state.hasSyncedBasalRateSchedule)

        let tempRate = Self.scheduledRate * 1.5
        XCTAssertNil(try enactTempBasal(unitsPerHour: tempRate, duration: .minutes(30)))
        let pump = try harness.client.snapshot().basal
        XCTAssertTrue(pump.tempActive)
        XCTAssertEqual(pump.tempRate, tempRate, accuracy: 0.001, "the pump delivers the rate the host was told")
    }

    // MARK: - S5

    /// A matching profile does not explain a live rate that differs, so the update does not end
    /// while the rate does; once the pump runs the schedule again it does, and temp basals resume.
    func testS5_aFailedUpdateRefusesTempBasalsUntilThePumpRunsTheScheduleAgain() throws {
        let driver = try stageDriver()
        try harness.client.setIDPProfiles([profile(rate: Self.scheduledRate)])
        try pumpRunsARateOffTheSchedule()

        _ = try sync()
        try clock.advanceBoth(seconds: TandemPumpManager.basalProfileUpdateTimeout + .minutes(1), ticks: 5)
        _ = try sync()
        XCTAssertEqual(driver.manager.state.basalProfileUpdateStatus, .failed)
        try assertTempBasalRefused(.failedUpdatePumpProfile)
        XCTAssertFalse(driver.manager.state.hasSyncedBasalRateSchedule, "the retry the failing reading queued read the rate off again")

        try harness.client.setState(["basal_rate": Self.scheduledRate])
        try clock.advanceBoth(seconds: TandemPumpManager.basalProfileUpdateRetryInterval, ticks: 1)
        _ = try sync()
        try waitForUpdate(.none, driver)

        XCTAssertNil(try enactTempBasal(unitsPerHour: Self.scheduledRate * 1.5, duration: .minutes(30)))
        XCTAssertTrue(driver.manager.state.hasSyncedBasalRateSchedule, "the profile read back matching")
        XCTAssertTrue(try harness.client.snapshot().basal.tempActive)
    }

    // MARK: - S6

    /// The pump runs a rate off the schedule before any reading has started an update. The percent
    /// is worked out against the pump's own rate, so the temp runs at the rate the host is told. The
    /// reading its `basalChange` event triggers then writes the schedule, and the temp the new
    /// profile would rescale is stopped.
    func testS6_aTempBasalOnAProfileThatDiffersRunsAtTheRequestedRate() throws {
        let driver = try stageDriver()
        try harness.client.setIDPProfiles([profile(rate: 0.8)])
        try harness.client.setState(["basal_rate": 0.8])
        let start = allPumpEventBatches.count

        XCTAssertNil(try enactTempBasal(unitsPerHour: 1.5, duration: .minutes(30)))

        let pumpTemp = try XCTUnwrap(try timeline().tempRates.first, "the pump recorded the temp rate")
        XCTAssertEqual(pumpTemp.percent, 188)
        let reported = try XCTUnwrap(tempBasalsReported(since: start).first?.dose)
        XCTAssertEqual(reported.unitsPerHour, try XCTUnwrap(pumpTemp.rate), accuracy: 0.01, "the host is told the rate the pump runs")

        try IntegrationWait.until("the schedule to be written over the profile", timeout: 30) {
            (try? self.harness.client.snapshot().basal.profileRate) == Self.scheduledRate
        }
        try waitForUpdate(.none, driver)
        XCTAssertFalse(try harness.client.snapshot().basal.tempActive, "the temp the new profile would rescale was stopped")
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
