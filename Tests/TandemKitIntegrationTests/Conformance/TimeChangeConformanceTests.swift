import Foundation
import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

/// Conformance group G (`docs/conformance-test-plan.md`): the time changes under the driver. A
/// Tandem pump holds a date and time with no zone and only moves when someone sets it, while the
/// driver decodes every pump timestamp with the phone's current UTC offset and corrects it by the
/// pump clock offset it last measured. So a phone that changes zone, and a pump whose clock is set
/// on the pump or by the app, each leave one side's local time behind the other's. Every dose must
/// still reach the host at the instant the pump delivered it.
///
/// Fixed-offset zones, so no DST transition lands inside a run; the driver reads only the phone's
/// current offset, which is all a DST transition changes.
final class TimeChangeConformanceTests: ConformanceTestCase {
    private static let profileRate = 1.0
    private static let eastern = "Etc/GMT+4"
    private static let easternStandard = "Etc/GMT+5"
    private static let pacific = "Etc/GMT+7"

    private var phone: PhoneTimeZone!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = true
        phone = PhoneTimeZone()
    }

    override func tearDownWithError() throws {
        if let harness {
            do {
                try harness.client.armFault(FaketandemFaultSpec(.radioOn))
                let snapshot = try harness.client.snapshot()
                if snapshot.bolus.active { try harness.client.abortBolus() }
                if snapshot.basal.tempActive { try harness.client.stopTempBasal() }
                if snapshot.basal.suspended { try harness.client.resume(clearAlarms: true) }
            } catch {
                XCTFail("restoring the pump's delivery state failed: \(error)")
            }
        }
        try super.tearDownWithError()
        phone?.restore()
        phone = nil
    }

    // MARK: - Staging

    /// Phone and pump on local time in `zone`, both history flags on, paired, synced and with the
    /// first backfill read finished.
    @discardableResult
    private func stageDriver(zone: String) throws -> FaketandemHarness.Driver {
        phone.set(zone)
        // Once the zone is named, an earlier scenario's records decode hours later (#482), later still
        // past any TimeChanged it left, and a fresh driver reports those that land in this scenario.
        try eraseHistory()
        try clock.start(at: clock.now, timezone: zone)
        try harness.client.setState(["basal_rate": Self.profileRate])
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.historyBackfill] = true
        state.featureFlags[.historyDoseReporting] = true
        state.bolusReportLedger = BolusReportLedger(trackingSince: clock.now)
        state.insulinType = .novolog
        state.basalRateSchedule = try XCTUnwrap(BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: Self.profileRate)]))
        let driver = startDriver(state: state)
        try harness.pair(driver)
        _ = try sync()
        try waitForBackfill(driver)
        XCTAssertFalse(driver.manager.state.showPumpTimeSyncWarning, "phone and pump agree at the start")
        return driver
    }

    private func waitForBackfill(_ driver: FaketandemHarness.Driver, timeout: TimeInterval = 180) throws {
        let last = try harness.client.snapshot().history.lastSequence
        try IntegrationWait.until("the driver to read the pump's history through \(last)", timeout: timeout) {
            (driver.manager.state.historyBackfill?.watermark).map { Int($0) >= last } == true
                && !driver.manager.historyFetchGate.isBusy
        }
    }

    private func radioOff(_ driver: FaketandemHarness.Driver) throws {
        try harness.client.armFault(FaketandemFaultSpec(.radioOff))
        try IntegrationWait.until("the emulator to drop the link", timeout: 30) {
            try !self.harness.client.snapshot().connection.connected
        }
        try IntegrationWait.until("the driver to notice the link is gone", timeout: 30) { !driver.manager.state.isConnected }
    }

    private func radioOn() throws {
        try harness.client.armFault(FaketandemFaultSpec(.radioOn))
    }

    private func syncPumpTime(timeout: TimeInterval? = nil) throws -> Result<Void, PumpManagerError> {
        let manager = try XCTUnwrap(current, "no driver").manager
        let box = ResultBox<Result<Void, PumpManagerError>>()
        manager.syncPumpTime { box.set($0) }
        let result = try box.wait("syncPumpTime completion", timeout: timeout ?? syncTimeout)
        drainDelegate()
        return result
    }

    /// A bolus programmed on the pump's own screen, run to completion. Returns its id and start.
    private func pumpBolus(units: Double) throws -> (bolusId: Int, start: Date) {
        let start = clock.now
        try harness.client.startBolus(units: units, rate: 0.05, source: "pump")
        let bolusId = try harness.client.snapshot().bolus.bolusId
        try advanceUntilBolusFinishes(bolusId: bolusId)
        return (bolusId, start)
    }

    /// An app bolus run to completion and finalized. Returns its start.
    private func appBolus(_ driver: FaketandemHarness.Driver, units: Double) throws -> (raw: Data, start: Date) {
        let start = clock.now
        let before = allPumpEventBatches.count
        XCTAssertNil(try enactBolus(units: units))
        let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        let raw = try XCTUnwrap(eventsSince(before).first { $0.dose?.type == .bolus }).raw
        try advanceUntilBolusFinishes(bolusId: bolusId)
        try clock.advanceBoth(seconds: driver.manager.estimatedDuration(toBolus: units) + .minutes(2))
        _ = try syncUntilFinalized(raw: raw)
        return (raw, start)
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

    private func pumpRecords(_ type: String) throws -> [FaketandemHistoryEntry] {
        try harness.client.history(since: historyStartSequence).filter { $0.type == type }
    }

    /// A completed pump bolus two hours before the driver began tracking the pump: inside the
    /// three hours a zone change west moves every record by, so only a corrected date keeps it out.
    private func stageBolusFromBeforeTracking(_ driver: FaketandemHarness.Driver) throws {
        try harness.client.appendHistory(type: "BolusActivated", secondsAgo: 7200, data: ["bolusId": Self.untrackedBolusId, "bolusSize": 1.0])
        try harness.client.appendHistory(type: "BolusCompleted", secondsAgo: 7180, data: [
            "completionStatusId": 3, "bolusId": Self.untrackedBolusId, "insulinDelivered": 1.0, "insulinRequested": 1.0,
        ])
        _ = try sync()
        try waitForBackfill(driver)
        XCTAssertTrue(eventsSince(0).filter { $0.dose?.type == .bolus }.isEmpty, "a bolus from before the driver tracked the pump is not reported")
    }

    private func assertHostsMatchThePump(file: StaticString = #filePath, line: UInt = #line) throws {
        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        // The staged bolus from before tracking is in the pump's record but rightly in no host's.
        let history = try harness.client.history(since: historyStartSequence)
            .filter { $0.data?["bolusId"]?.intValue != Self.untrackedBolusId }
        let timeline = PumpTimeline.build(
            snapshot: try harness.client.snapshot(),
            history: history,
            log: try harness.requestLog(since: logStartSequence),
            afterSequence: historyStartSequence
        )
        timeline.assertMatches(loop, file: file, line: line)
    }

    private static let untrackedBolusId = 4242

    // MARK: - G1

    /// The phone moves three hours west and nobody sets the pump, which keeps eastern time. Every
    /// pump timestamp now decodes three hours late; the driver measures that as a pump clock three
    /// hours fast, warns, and takes it back out of what it reports.
    func testG1_phoneChangesZoneAndThePumpIsNotTold() throws {
        let driver = try stageDriver(zone: Self.eastern)
        let batchesBefore = allPumpEventBatches.count

        phone.set(Self.pacific)
        _ = try sync()
        XCTAssertEqual(driver.manager.state.pumpClockOffset, .hours(3), accuracy: 2, "the pump reads eastern time")
        XCTAssertTrue(driver.manager.state.showPumpTimeSyncWarning)

        let app = try appBolus(driver, units: 1.0)
        let appReport = try XCTUnwrap(eventsSince(batchesBefore).last { $0.raw == app.raw && $0.dose?.isMutable == false })
        XCTAssertEqual(try XCTUnwrap(appReport.dose?.startDate).timeIntervalSince(app.start), 0, accuracy: 2, "the app's bolus at the instant it started")

        try radioOff(driver)
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        let stoppedAt = clock.now
        _ = try harness.client.suspend(reason: "user")
        try clock.advanceBoth(seconds: .minutes(10), ticks: 10)
        let resumedAt = clock.now
        _ = try harness.client.resume(clearAlarms: true)
        try clock.advanceBoth(seconds: .minutes(2), ticks: 2)
        let pump = try pumpBolus(units: 0.5)
        try clock.advanceBoth(seconds: .minutes(2), ticks: 2)
        try radioOn()
        _ = try sync()

        let suspend = try waitForEvent("the suspend from the pump's history", since: batchesBefore) { $0.type == .suspend }
        let resume = try waitForEvent("the resume from the pump's history", since: batchesBefore) { $0.type == .resume }
        XCTAssertEqual(suspend.date.timeIntervalSince(stoppedAt), 0, accuracy: 1)
        XCTAssertEqual(resume.date.timeIntervalSince(resumedAt), 0, accuracy: 1)

        let pumpReport = try waitForEvent("the pump's bolus from its history", since: batchesBefore) {
            $0.dose?.type == .bolus && $0.dose?.wasProgrammedByPumpUI == true
        }
        XCTAssertEqual(try XCTUnwrap(pumpReport.dose?.startDate).timeIntervalSince(pump.start), 0, accuracy: 2, "the pump's bolus at the instant it started")

        try assertHostsMatchThePump()
    }

    // MARK: - G2

    /// The phone moves three hours west while the pump is out of range, and the app sets the pump
    /// to the phone's time once it is back. Everything the pump logged before the change is read
    /// after it, so its stamps are three hours ahead of the clock now in force; the pump's
    /// `TimeChanged` record says by how much.
    func testG2_phoneChangesZoneAndTheAppSetsThePumpsClock() throws {
        let driver = try stageDriver(zone: Self.eastern)
        try stageBolusFromBeforeTracking(driver)
        let batchesBefore = allPumpEventBatches.count
        let rate = 1.5
        let duration: TimeInterval = .minutes(60)

        XCTAssertNil(try enactTempBasal(unitsPerHour: rate, duration: duration))
        let tempStart = try XCTUnwrap(eventsSince(batchesBefore).first { $0.dose?.type == .tempBasal }?.dose?.startDate)

        try radioOff(driver)
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        let pump = try pumpBolus(units: 0.5)
        phone.set(Self.pacific)
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        try radioOn()

        let changeLogMark = try harness.client.snapshot().requestLog.lastSeq
        let synced = try syncPumpTime()
        XCTAssertNoThrow(try synced.get())
        XCTAssertTrue(try harness.requestsSeen(since: changeLogMark).contains { $0.message == "ChangeTimeDateRequest" })
        XCTAssertEqual(try harness.client.clock().pumpTimezoneOffsetSeconds, -7 * 3600, "the pump now reads pacific time")
        XCTAssertEqual(try pumpRecords("TimeChanged").count, 1)
        _ = try sync()
        XCTAssertEqual(driver.manager.state.pumpClockOffset, 0, accuracy: 2)
        XCTAssertFalse(driver.manager.state.showPumpTimeSyncWarning)

        let pumpReport = try waitForEvent("the pump's bolus from its history", since: batchesBefore) {
            $0.dose?.type == .bolus && $0.dose?.wasProgrammedByPumpUI == true && $0.dose?.programmedUnits == 0.5
        }
        XCTAssertEqual(try XCTUnwrap(pumpReport.dose?.startDate).timeIntervalSince(pump.start), 0, accuracy: 2, "logged before the change, dated at the instant it started")
        let old = eventsSince(batchesBefore).filter { $0.dose?.type == .bolus && $0.dose?.programmedUnits == 1.0 }
        XCTAssertTrue(old.isEmpty, "a bolus from before the driver tracked the pump was reported: \(old)")

        // The temp basal started before the change and runs out after it.
        try clock.advanceBoth(seconds: tempStart.addingTimeInterval(duration).timeIntervalSince(clock.now) + 30, ticks: 10)
        _ = try sync()
        let finished = try waitForEvent("the temp basal finalized", since: batchesBefore) {
            $0.dose?.type == .tempBasal && $0.dose?.isMutable == false && $0.dose?.startDate == tempStart
        }
        XCTAssertEqual(try XCTUnwrap(finished.dose?.endDate).timeIntervalSince(tempStart), duration, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(finished.dose?.deliveredUnits), rate, accuracy: 0.001)

        // After the change, on the new clock.
        let stoppedAt = clock.now
        _ = try harness.client.suspend(reason: "user")
        let suspend = try waitForEvent("the suspend", since: batchesBefore) { $0.type == .suspend }
        XCTAssertEqual(suspend.date.timeIntervalSince(stoppedAt), 0, accuracy: 1)
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        _ = try harness.client.resume(clearAlarms: true)
        _ = try waitForEvent("the resume", since: batchesBefore) { $0.type == .resume }

        try assertHostsMatchThePump()
    }

    // MARK: - G3

    /// The user sets the pump an hour ahead on the pump itself, during an outage in which the pump
    /// also stops and starts again; the phone stays as it was. Records either side of the change are
    /// stamped on different clocks. The app then sets the pump back to the phone's time.
    func testG3_theUserSetsThePumpsClockOnThePump() throws {
        let driver = try stageDriver(zone: Self.eastern)
        let batchesBefore = allPumpEventBatches.count

        try radioOff(driver)
        try clock.advanceBoth(seconds: .minutes(2), ticks: 2)
        let stoppedAt = clock.now
        _ = try harness.client.suspend(reason: "user")
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        try harness.client.setPumpTimeOnThePump(deltaSeconds: .hours(1))
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        let resumedAt = clock.now
        _ = try harness.client.resume(clearAlarms: true)
        try clock.advanceBoth(seconds: .minutes(2), ticks: 2)
        let pump = try pumpBolus(units: 0.5)
        try clock.advanceBoth(seconds: .minutes(2), ticks: 2)
        try radioOn()
        _ = try sync()

        XCTAssertEqual(driver.manager.state.pumpClockOffset, .hours(1), accuracy: 2)
        XCTAssertTrue(driver.manager.state.showPumpTimeSyncWarning)
        let suspend = try waitForEvent("the suspend from the pump's history", since: batchesBefore) { $0.type == .suspend }
        let resume = try waitForEvent("the resume from the pump's history", since: batchesBefore) { $0.type == .resume }
        XCTAssertEqual(suspend.date.timeIntervalSince(stoppedAt), 0, accuracy: 1, "logged before the change")
        XCTAssertEqual(resume.date.timeIntervalSince(resumedAt), 0, accuracy: 1, "logged after the change")
        let pumpReport = try waitForEvent("the pump's bolus from its history", since: batchesBefore) {
            $0.dose?.type == .bolus && $0.dose?.wasProgrammedByPumpUI == true
        }
        XCTAssertEqual(try XCTUnwrap(pumpReport.dose?.startDate).timeIntervalSince(pump.start), 0, accuracy: 2, "logged after the change")

        XCTAssertNoThrow(try syncPumpTime().get())
        XCTAssertEqual(try pumpRecords("TimeChanged").count, 2, "the user's change and the app's")
        XCTAssertEqual(driver.manager.state.pumpClockOffset, 0, accuracy: 2)
        XCTAssertFalse(driver.manager.state.showPumpTimeSyncWarning)

        let app = try appBolus(driver, units: 1.0)
        let appReport = try XCTUnwrap(eventsSince(batchesBefore).last { $0.raw == app.raw && $0.dose?.isMutable == false })
        XCTAssertEqual(try XCTUnwrap(appReport.dose?.startDate).timeIntervalSince(app.start), 0, accuracy: 2)

        try assertHostsMatchThePump()
    }

    // MARK: - G4

    /// The phone's offset drops an hour between syncs (a DST fall-back), the pump is left alone,
    /// and the pump stops before the driver has measured its clock again. Every pump record now
    /// decodes an hour later, so a bolus the pump logged before the driver began tracking it moves
    /// past the reporting floor.
    func testG4_phoneOffsetChangesBetweenSyncsAndThePumpStopsFirst() throws {
        let driver = try stageDriver(zone: Self.eastern)
        // Decodes 10 minutes after tracking began: past the floor, and ended before the hosts are
        // compared, which Loop needs to count it.
        try harness.client.appendHistory(type: "BolusActivated", secondsAgo: 3000, data: ["bolusId": Self.untrackedBolusId, "bolusSize": 1.0])
        try harness.client.appendHistory(type: "BolusCompleted", secondsAgo: 2980, data: [
            "completionStatusId": 3, "bolusId": Self.untrackedBolusId, "insulinDelivered": 1.0, "insulinRequested": 1.0,
        ])
        _ = try sync()
        try waitForBackfill(driver)
        let batchesBefore = allPumpEventBatches.count
        XCTAssertTrue(eventsSince(0).filter { $0.dose?.type == .bolus }.isEmpty, "a bolus from before the driver tracked the pump is not reported")

        phone.set(Self.easternStandard)
        try clock.advanceBoth(seconds: .minutes(3), ticks: 3)
        let stoppedAt = clock.now
        _ = try harness.client.suspend(reason: "user")
        let suspend = try waitForEvent("the suspend after the pump's qualifying event", since: batchesBefore) { $0.type == .suspend }
        XCTAssertEqual(suspend.date.timeIntervalSince(stoppedAt), 0, accuracy: 1)

        try radioOff(driver)
        try clock.advanceBoth(seconds: .minutes(10), ticks: 10)
        let resumedAt = clock.now
        _ = try harness.client.resume(clearAlarms: true)
        try clock.advanceBoth(seconds: .minutes(10), ticks: 10)
        try radioOn()
        _ = try sync()
        let resume = try waitForEvent("the resume from the pump's history", since: batchesBefore) { $0.type == .resume }
        XCTAssertEqual(resume.date.timeIntervalSince(resumedAt), 0, accuracy: 1)
        XCTAssertEqual(driver.manager.state.pumpClockOffset, .hours(1), accuracy: 2, "the pump still reads daylight time")

        let boluses = eventsSince(batchesBefore).filter { $0.dose?.type == .bolus }
        XCTAssertTrue(boluses.isEmpty, "a bolus from before the driver tracked the pump was reported after the offset change: \(boluses)")
        try assertHostsMatchThePump()
    }
}
