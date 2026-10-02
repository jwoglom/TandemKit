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
/// `basalMismatchConfirmationInterval`, and a schedule change that alters the rate in force stops a
/// running temp basal instead of leaving the pump to rescale it.
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
}
