import Foundation
import LoopKit
@testable import TandemKit
import XCTest

/// Conformance group F (`docs/conformance-test-plan.md`): the pump changes delivery while the
/// phone is out of range. The pump's radio goes off, the pump stops or resumes on its own, time
/// passes, the radio comes back and the driver syncs. The question is whether the host learns when
/// delivery actually stopped and started, from the pump's history (#333), rather than when the
/// driver next looked.
///
/// Every scenario runs with the History Backfill flag on, since that is what reads the pump's
/// history, and ends with the pump-timeline diff.
final class OutageConformanceTests: ConformanceTestCase {
    private static let profileRate = 1.0
    private static let outage: TimeInterval = .minutes(20)

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = true
        let snapshot = try harness.client.snapshot()
        if snapshot.bolus.active || snapshot.basal.tempActive || snapshot.basal.suspended {
            try restorePumpDelivery(harness.client)
        }
    }

    override func tearDownWithError() throws {
        if let harness {
            do {
                try harness.client.armFault(FaketandemFaultSpec(.radioOn))
                try restorePumpDelivery(harness.client)
            } catch {
                XCTFail("restoring the pump's delivery state failed: \(error)")
            }
        }
        try super.tearDownWithError()
    }

    private func restorePumpDelivery(_ client: FaketandemClient) throws {
        let snapshot = try client.snapshot()
        if snapshot.bolus.active {
            try client.abortBolus()
        }
        if snapshot.basal.tempActive {
            try client.stopTempBasal()
        }
        if snapshot.basal.suspended {
            try client.resume(clearAlarms: true)
        }
    }

    // MARK: - Staging

    /// A paired driver with history backfill on, synced, with its first backfill read finished so
    /// the outage does not cut a read short.
    @discardableResult
    private func stageDriver() throws -> FaketandemHarness.Driver {
        try harness.client.setState(["basal_rate": Self.profileRate])
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.historyBackfill] = true
        let driver = startDriver(state: state)
        driver.manager.state.insulinType = .novolog
        driver.manager.state.basalRateSchedule = BasalRateSchedule(
            dailyItems: [RepeatingScheduleValue(startTime: 0, value: Self.profileRate)]
        )!
        try harness.pair(driver)
        _ = try sync()
        try waitForBackfill(driver)
        return driver
    }

    private func waitForBackfill(_ driver: FaketandemHarness.Driver, timeout: TimeInterval = 180) throws {
        let last = try harness.client.snapshot().history.lastSequence
        try IntegrationWait.until("the driver to read the pump's history through \(last)", timeout: timeout) {
            (driver.manager.state.historyBackfill?.watermark).map { Int($0) >= last } == true
                && !driver.manager.historyFetchGate.isBusy
        }
    }

    /// The pump goes out of range: it drops the link and refuses to reconnect.
    private func radioOff(_ driver: FaketandemHarness.Driver) throws {
        try harness.client.armFault(FaketandemFaultSpec(.radioOff))
        try IntegrationWait.until("the emulator to drop the link", timeout: 30) {
            try !self.harness.client.snapshot().connection.connected
        }
        try IntegrationWait.until("the driver to notice the link is gone", timeout: 30) { !driver.manager.state.isConnected }
    }

    /// Back in range; the sync reconnects rather than waiting on auto-reconnect (#351).
    private func radioOnAndSync() throws {
        try harness.client.armFault(FaketandemFaultSpec(.radioOn))
        _ = try sync()
    }

    private func eventsSince(_ count: Int) -> [NewPumpEvent] {
        Array(allPumpEventBatches.dropFirst(count)).flatMap(\.events)
    }

    private func waitForEvent(
        _ what: String,
        since count: Int,
        timeout: TimeInterval = 120,
        _ matches: @escaping (NewPumpEvent) -> Bool
    ) throws -> NewPumpEvent {
        try IntegrationWait.value(what, timeout: timeout) {
            self.eventsSince(count).first(where: matches)
        }
    }

    // MARK: - F1

    /// The pump stops while out of range and is still stopped when the phone is back: the suspend
    /// is dated at the stop, not at the reconnect.
    func testF1_stopDuringAnOutageIsDatedAtTheStop() throws {
        let driver = try stageDriver()
        let batchesBefore = allPumpEventBatches.count

        try radioOff(driver)
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        let stoppedAt = clock.now
        _ = try harness.client.suspend(reason: "occlusion")
        try clock.advanceBoth(seconds: Self.outage, ticks: 20)
        let reconnectedAt = clock.now
        try radioOnAndSync()

        let suspend = try waitForEvent("the suspend from the pump's history", since: batchesBefore) { $0.type == .suspend }
        XCTAssertEqual(suspend.date.timeIntervalSince(stoppedAt), 0, accuracy: 1, "dated at the pump's stop, not at \(reconnectedAt)")
        XCTAssertEqual(suspend.dose?.startDate.timeIntervalSince(stoppedAt) ?? .infinity, 0, accuracy: 1)
        XCTAssertEqual(suspend.dose?.isMutable, false)
        XCTAssertEqual(eventsSince(batchesBefore).filter { $0.type == .suspend }.count, 1, "one suspend for one stop: \(eventsSince(batchesBefore))")
        XCTAssertEqual(driver.manager.state.basalDose.type, .suspend)
        XCTAssertEqual(driver.manager.state.basalDose.startDate.timeIntervalSince(stoppedAt), 0, accuracy: 1)

        // Back in range, the pump resumes; the host closes the suspend at the pump's resume.
        try clock.advanceBoth(seconds: .minutes(2), ticks: 2)
        let resumedAt = clock.now
        _ = try harness.client.resume(clearAlarms: true)
        _ = try sync()
        let resume = try waitForEvent("the resume", since: batchesBefore) { $0.type == .resume }
        XCTAssertEqual(resume.date.timeIntervalSince(resumedAt), 0, accuracy: 1)

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        let stored = try XCTUnwrap(loop.doses.first { $0.dose.type == .suspend }, "Loop: \(loop.doses.map(LoopDoseStoreOracle.describe))")
        XCTAssertFalse(stored.isMutable, "the resume closes the suspend")
        XCTAssertEqual(stored.dose.endDate.timeIntervalSince(stoppedAt), resumedAt.timeIntervalSince(stoppedAt), accuracy: 2, "suspend duration")
        XCTAssertEqual(trio.suspends.map(\.timestamp), [suspend.date])
        XCTAssertEqual(trio.resumes.count, 1)

        let timeline = try timeline()
        XCTAssertEqual(timeline.suspends.count, 1, "timeline: \(timeline)")
        timeline.assertMatches(loop)
    }

    // MARK: - F2

    /// The pump stops and starts again while out of range. The driver's reads either side of the
    /// outage both show basal running, so only the history shows the stop.
    func testF2_stopAndResumeInsideAnOutageAreReportedAsAPair() throws {
        let driver = try stageDriver()
        let batchesBefore = allPumpEventBatches.count

        try radioOff(driver)
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        let stoppedAt = clock.now
        _ = try harness.client.suspend(reason: "occlusion")
        try clock.advanceBoth(seconds: .minutes(10), ticks: 10)
        let resumedAt = clock.now
        _ = try harness.client.resume(clearAlarms: true)
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        try radioOnAndSync()

        let suspend = try waitForEvent("the suspend from the pump's history", since: batchesBefore) { $0.type == .suspend }
        let resume = try waitForEvent("the resume from the pump's history", since: batchesBefore) { $0.type == .resume }
        XCTAssertEqual(suspend.date.timeIntervalSince(stoppedAt), 0, accuracy: 1)
        XCTAssertEqual(resume.date.timeIntervalSince(resumedAt), 0, accuracy: 1)
        XCTAssertEqual(eventsSince(batchesBefore).filter { $0.type == .suspend }.count, 1)
        XCTAssertEqual(eventsSince(batchesBefore).filter { $0.type == .resume }.count, 1)
        XCTAssertNotEqual(driver.manager.state.basalDose.type, .suspend, "the pump is delivering")

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        let stored = try XCTUnwrap(loop.doses.first { $0.dose.type == .suspend }, "Loop: \(loop.doses.map(LoopDoseStoreOracle.describe))")
        XCTAssertFalse(stored.isMutable)
        XCTAssertEqual(stored.dose.endDate.timeIntervalSince(stored.dose.startDate), .minutes(10), accuracy: 2, "ten minutes suspended")
        XCTAssertEqual(trio.suspends.count, 1)
        XCTAssertEqual(trio.resumes.count, 1)

        try timeline().assertMatches(loop)
    }

    // MARK: - F3

    /// The app suspends; the pump is resumed while out of range. The host gets a `.resume` at the
    /// pump's restart, not a scheduled-basal marker at the reconnect (#331), and the app's own
    /// suspend is not reported a second time from history.
    func testF3_resumeDuringAnOutageAfterAnAppSuspend() throws {
        let driver = try stageDriver()
        let batchesBefore = allPumpEventBatches.count

        XCTAssertNil(try suspendDelivery())
        let appSuspend = try XCTUnwrap(eventsSince(batchesBefore).first { $0.type == .suspend })

        try radioOff(driver)
        try clock.advanceBoth(seconds: .minutes(10), ticks: 10)
        let resumedAt = clock.now
        _ = try harness.client.resume(clearAlarms: true)
        try clock.advanceBoth(seconds: .minutes(10), ticks: 10)
        try radioOnAndSync()

        let resume = try waitForEvent("the resume from the pump's history", since: batchesBefore) { $0.type == .resume }
        XCTAssertEqual(resume.date.timeIntervalSince(resumedAt), 0, accuracy: 1, "dated at the pump's restart")
        XCTAssertEqual(resume.dose?.isMutable, false)
        let suspends = eventsSince(batchesBefore).filter { $0.type == .suspend }
        XCTAssertEqual(suspends.map(\.raw), [appSuspend.raw], "the app's suspend, once: \(suspends)")
        XCTAssertEqual(driver.manager.state.basalDose.type, .resume)

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        let stored = try XCTUnwrap(loop.doses.first { $0.dose.type == .suspend })
        XCTAssertFalse(stored.isMutable, "the resume closes the app's suspend")
        XCTAssertEqual(stored.dose.endDate.timeIntervalSince(resumedAt), 0, accuracy: 2)
        XCTAssertEqual(trio.suspends.count, 1)
        XCTAssertEqual(trio.resumes.map(\.timestamp), [resume.date], "Trio's suspend is closed, so basal IOB is not zeroed")

        try timeline().assertMatches(loop)
    }

    // MARK: - F4

    /// A temp basal is running when the phone goes out of range, and an occlusion stops the pump,
    /// ending the temp rate. The temp basal ends, and its delivered units stop, at the occlusion.
    func testF4_tempBasalStoppedByAnOcclusionDuringAnOutage() throws {
        let driver = try stageDriver()
        let batchesBefore = allPumpEventBatches.count
        let rate = 1.5
        let duration: TimeInterval = .minutes(60)

        XCTAssertNil(try enactTempBasal(unitsPerHour: rate, duration: duration))
        let started = try XCTUnwrap(eventsSince(batchesBefore).first { $0.dose?.type == .tempBasal })
        let start = try XCTUnwrap(started.dose?.startDate)

        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        try radioOff(driver)
        try clock.advanceBoth(seconds: .minutes(3), ticks: 3)
        let stoppedAt = clock.now
        _ = try harness.client.suspend(reason: "occlusion")
        XCTAssertFalse(try harness.client.snapshot().basal.tempActive, "the stop ended the temp rate")
        try clock.advanceBoth(seconds: Self.outage, ticks: 20)
        try radioOnAndSync()

        let finished = try waitForEvent("the finished temp basal", since: batchesBefore) {
            $0.dose?.type == .tempBasal && $0.dose?.isMutable == false && $0.dose?.startDate == start
        }
        XCTAssertEqual(try XCTUnwrap(finished.dose?.endDate).timeIntervalSince(stoppedAt), 0, accuracy: 1, "ended at the occlusion")
        XCTAssertEqual(try XCTUnwrap(finished.dose?.deliveredUnits), rate * stoppedAt.timeIntervalSince(start) / .hours(1), accuracy: 0.001)
        let suspend = try waitForEvent("the suspend", since: batchesBefore) { $0.type == .suspend }
        XCTAssertEqual(suspend.date.timeIntervalSince(stoppedAt), 0, accuracy: 1)
        XCTAssertEqual(driver.manager.state.basalDose.type, .suspend)

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        let stored = try XCTUnwrap(loop.doses.first { $0.dose.type == .tempBasal && $0.dose.startDate == start })
        XCTAssertFalse(stored.isMutable)
        XCTAssertEqual(stored.dose.endDate.timeIntervalSince(stoppedAt), 0, accuracy: 1)
        XCTAssertEqual(trio.tempBasals.count, 1, "one temp basal row: \(trio.tempBasals)")
        XCTAssertEqual(trio.suspends.count, 1)

        let timeline = try timeline()
        let pumpTemp = try XCTUnwrap(timeline.tempRates.first, "timeline: \(timeline)")
        XCTAssertTrue(pumpTemp.isFinished)
        timeline.assertMatches(loop)
    }
}
