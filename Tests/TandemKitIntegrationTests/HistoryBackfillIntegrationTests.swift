import Foundation
import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

/// History backfill against a pump with a real log (AGENTS.md "History backfill and dose
/// reporting"): what is read and how, measured from the pump's request log, and what reaches the
/// host. The planner and coordinator are unit-tested; these run them over the virtual link against
/// logs thousands of records long.
final class HistoryBackfillIntegrationTests: ConformanceTestCase {
    private static let profileRate = 1.0
    private static let sliceSize = Int(HistoryBackfillPlanner.maxDeepSliceSize)

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = true
    }

    // MARK: - Staging

    /// `trackingSince` before now stands for a setup history load the user accepted.
    @discardableResult
    private func stageDriver(backfill: Bool = true, doseReporting: Bool = true, trackingSince: Date? = nil) throws -> FaketandemHarness.Driver {
        try harness.client.setState(["basal_rate": Self.profileRate])
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.historyBackfill] = backfill
        state.featureFlags[.historyDoseReporting] = doseReporting
        state.bolusReportLedger = BolusReportLedger(trackingSince: trackingSince ?? clock.now)
        state.insulinType = .novolog
        state.basalRateSchedule = try XCTUnwrap(BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: Self.profileRate)]))
        let driver = startDriver(state: state)
        try harness.pair(driver)
        _ = try sync()
        if backfill {
            try waitForBackfill(driver)
        }
        return driver
    }

    private func waitForBackfill(_ driver: FaketandemHarness.Driver, timeout: TimeInterval = 300) throws {
        let last = try harness.client.snapshot().history.lastSequence
        try IntegrationWait.until("the driver to read the pump's history through \(last)", timeout: timeout) {
            (driver.manager.state.historyBackfill?.watermark).map { Int($0) >= last } == true
                && !driver.manager.historyFetchGate.isBusy
        }
    }

    /// Records the pump writes every `spacing` seconds up to now, oldest first; returns the
    /// sequence numbers of the first and last.
    @discardableResult
    private func pumpLogs(count: Int, spacing: TimeInterval) throws -> ClosedRange<Int> {
        let records: [[String: Any]] = (0 ..< count).map { i in
            [
                "type": "BasalDelivery",
                "seconds_ago": Double(count - 1 - i) * spacing,
                "data": ["commandedRate": 1000, "profileBasalRate": 1000],
            ]
        }
        return try harness.client.appendHistory(records: records)
    }

    /// The `HistoryLogRequest`s since `mark`, as the slices they asked for.
    private func historyReads(since mark: Int) throws -> [ClosedRange<Int>] {
        try harness.requestLog(since: mark).compactMap { entry in
            guard entry.isRequest, entry.message == "HistoryLogRequest",
                  let top = entry.cargo?["startLog"]?.intValue,
                  let count = entry.cargo?["numberOfLogs"]?.intValue,
                  top >= 1
            else { return nil }
            return max(1, top - max(count, 1) + 1) ... top
        }
    }

    private func logMark() throws -> Int {
        try harness.client.snapshot().requestLog.lastSeq
    }

    private func missingFromSessionStore(_ driver: FaketandemHarness.Driver, _ range: ClosedRange<Int>) throws -> [ClosedRange<UInt32>] {
        let serial = try XCTUnwrap(driver.manager.historyLogStoreSerial)
        return try driver.manager.historyLogStore.missingRanges(
            pumpSerial: serial.rawValue,
            in: UInt32(range.lowerBound) ... UInt32(range.upperBound)
        )
    }

    private func eventsSince(_ count: Int) -> [NewPumpEvent] {
        Array(allPumpEventBatches.dropFirst(count)).flatMap(\.events)
    }

    private func waitForEvent(_ what: String, since count: Int, timeout: TimeInterval = 120, _ matches: @escaping (NewPumpEvent) -> Bool) throws -> NewPumpEvent {
        try IntegrationWait.value(what, timeout: timeout) { self.eventsSince(count).first(where: matches) }
    }

    /// A bolus programmed on the pump's screen, run to completion.
    private func pumpBolus(units: Double) throws -> (bolusId: Int, start: Date) {
        let start = clock.now
        try harness.client.startBolus(units: units, rate: 0.05, source: "pump")
        let bolusId = try harness.client.snapshot().bolus.bolusId
        try advanceUntilBolusFinishes(bolusId: bolusId)
        return (bolusId, start)
    }

    // MARK: - H1

    /// Off means the pump's history is never read: not on pairing, a sync, a bolus, a temp basal,
    /// a suspend or resume either side, or a qualifying event that would otherwise kick a tick.
    func testWithHistoryBackfillOffThePumpsHistoryIsNeverRead() throws {
        let mark = try logMark()
        let driver = try stageDriver(backfill: false, doseReporting: false)

        XCTAssertNil(try enactBolus(units: 0.5))
        let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        try advanceUntilBolusFinishes(bolusId: bolusId)
        try clock.advanceBoth(seconds: driver.manager.estimatedDuration(toBolus: 0.5) + .minutes(2))
        _ = try sync()
        XCTAssertNil(try enactTempBasal(unitsPerHour: 1.5, duration: .minutes(30)))
        XCTAssertNil(try enactTempBasal(unitsPerHour: 0, duration: 0))
        XCTAssertNil(try suspendDelivery())
        XCTAssertNil(try resumeDelivery())
        _ = try harness.client.suspend(reason: "user")
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        _ = try harness.client.resume(clearAlarms: true)
        try harness.client.raiseQualifyingEvent(bitmask: QualifyingEvent.bolusChange.id)
        _ = try sync()
        drainDelegate()

        let read = try harness.requestsSeen(since: mark).map(\.message).filter { $0.hasPrefix("HistoryLog") }
        XCTAssertTrue(read.isEmpty, "the pump's history was read: \(read)")
        XCTAssertNil(driver.manager.state.historyBackfill, "no bookkeeping for a log never read")
    }

    // MARK: - H2

    /// A pump seen for the first time with two days of history: nothing from before the driver
    /// first saw it is read or reported, however long the log.
    func testFirstSightOfALongLogReadsNothingFromBeforeIt() throws {
        let staged = try pumpLogs(count: 3000, spacing: 60)
        let pumpBolusRecord = try harness.client.appendHistory(type: "BolusCompleted", secondsAgo: 600, data: [
            "completionStatusId": 3, "bolusId": 4321, "insulinDelivered": 1.0, "insulinRequested": 1.0,
        ])
        let mark = try logMark()
        let driver = try stageDriver()

        let reads = try historyReads(since: mark)
        let lowest = reads.map(\.lowerBound).min() ?? Int.max
        XCTAssertGreaterThan(lowest, staged.upperBound - Self.sliceSize, "read back into the pump's pre-service history: \(reads)")
        XCTAssertTrue(eventsSince(0).filter { $0.dose?.type == .bolus }.isEmpty, "a bolus from before the driver saw the pump was reported")
        XCTAssertNotNil(driver.manager.state.historyBackfill?.firstSeenFloor)
        XCTAssertEqual(pumpBolusRecord.history.lastSequence, staged.upperBound + 1)
    }

    // MARK: - H3

    /// After a relaunch the session store is empty, so the next tick walks back over the seven
    /// hours of insulin that may still be acting, in slices of one `HistoryLogRequest`, stopping
    /// within one slice of the lookback and at most `maxDeepSlicesPerTick` slices per tick.
    func testAfterARelaunchTheWalkReReadsTheLookbackInSlices() throws {
        try stageDriver()
        let hours: TimeInterval = 8
        try clock.advanceBoth(seconds: .hours(hours), ticks: 8)
        // One record every 5 s: more than `maxDeepSlicesPerTick` slices inside the lookback.
        let spacing: TimeInterval = 5
        let staged = try pumpLogs(count: Int(.hours(hours) / spacing), spacing: spacing)
        _ = try sync()
        let driver = try XCTUnwrap(current)
        try waitForBackfill(driver, timeout: 600)

        let relaunched = try relaunch()
        let mark = try logMark()
        let lookbackStart = staged.upperBound - Int(HistoryBackfillPlanner.deepFetchLookback / spacing)
        var syncs = 0
        // Each sync kicks one tick; the walk needs more slices than one tick may take.
        repeat {
            _ = try sync()
            try IntegrationWait.until("the tick to finish", timeout: 600) { !relaunched.manager.historyFetchGate.isBusy }
            syncs += 1
        } while try !missingFromSessionStore(relaunched, lookbackStart ... staged.upperBound).isEmpty && syncs < 4
        XCTAssertTrue(try missingFromSessionStore(relaunched, lookbackStart ... staged.upperBound).isEmpty, "the walk never covered the lookback")

        let reads = try historyReads(since: mark)
        XCTAssertTrue(reads.allSatisfy { $0.count <= Self.sliceSize }, "a request asked for more than one slice: \(reads)")
        let lowest = reads.map(\.lowerBound).min() ?? Int.max
        XCTAssertGreaterThanOrEqual(lowest, lookbackStart - Self.sliceSize, "the walk read past the lookback: lowest \(lowest), lookback starts at \(lookbackStart)")
        XCTAssertGreaterThan(
            reads.count,
            HistoryBackfillPlanner.maxDeepSlicesPerTick,
            "the lookback needs more slices than one tick may walk, so a second tick finished it: \(reads.count) reads"
        )
    }

    // MARK: - H4

    /// A bolus enacted while the walk runs goes out after at most the slice in flight.
    func testABolusDuringALongWalkWaitsForOneSliceAtMost() throws {
        try stageDriver()
        try clock.advanceBoth(seconds: .hours(7), ticks: 7)
        let staged = try pumpLogs(count: 4000, spacing: 6)
        _ = try sync()
        let driver = try XCTUnwrap(current)
        try waitForBackfill(driver, timeout: 600)
        let relaunched = try relaunch()
        // Over the virtual link a whole walk outruns the test; at a pump's pace it does not.
        var slowSlices = FaketandemFaultSpec(.delayResponse, message: "HistoryLogRequest")
        slowSlices.delayMilliseconds = 400
        slowSlices.every = true
        XCTAssertNotNil(try harness.client.armFault(slowSlices))

        let mark = try logMark()
        let syncBox = ResultBox<Date?>()
        relaunched.manager.syncPumpData { syncBox.set($0) }
        try IntegrationWait.until("the walk to start", timeout: 60) {
            try self.historyReads(since: mark).count >= 2
        }
        XCTAssertNil(try enactBolus(units: 0.5))
        let bolusId = try XCTUnwrap(relaunched.manager.state.bolusDose?.bolusId)
        _ = try syncBox.wait("the sync", timeout: syncTimeout)

        try IntegrationWait.until("the walk to finish", timeout: 900) {
            try self.missingFromSessionStore(relaunched, staged.upperBound - 1000 ... staged.upperBound).isEmpty
        }

        let log = try harness.requestLog(since: mark).filter(\.isRequest)
        let bolusAt = try XCTUnwrap(log.firstIndex { $0.message == "InitiateBolusRequest" }, "the bolus never went out")
        let readsBefore = log[..<bolusAt].filter { $0.message == "HistoryLogRequest" }.count
        let readsAfter = log[bolusAt...].filter { $0.message == "HistoryLogRequest" }.count
        XCTAssertGreaterThan(readsAfter, 0, "the bolus waited for the whole walk (\(readsBefore) reads before it)")
        XCTAssertLessThanOrEqual(readsBefore, 3, "the bolus waited for more than the slice in flight")
        try advanceUntilBolusFinishes(bolusId: bolusId)
    }

    // MARK: - H5

    /// A record lost from a history stream is asked for again in the same fetch, and what it held
    /// reaches the host once.
    func testARecordLostFromAStreamIsReadAgain() throws {
        let driver = try stageDriver()
        let batchesBefore = allPumpEventBatches.count
        var fault = FaketandemFaultSpec(.dropResponse, message: "HistoryLogStreamResponse")
        fault.count = 1
        XCTAssertNotNil(try harness.client.armFault(fault))
        let mark = try logMark()

        let pump = try pumpBolus(units: 0.5)
        let completed = try harness.client.snapshot().history.lastSequence
        _ = try sync()
        try waitForBackfill(driver)

        let reads = try historyReads(since: mark)
        XCTAssertTrue(try harness.requestLog(since: mark).contains { $0.fault == "drop_response" }, "the fault fired")
        let lowest = try XCTUnwrap(reads.map(\.lowerBound).min())
        XCTAssertTrue(try missingFromSessionStore(driver, lowest ... completed).isEmpty, "a lost record stayed lost: \(reads)")
        let readTwice = (lowest ... completed).contains { seq in reads.filter { $0.contains(seq) }.count > 1 }
        XCTAssertTrue(readTwice, "nothing was asked for again: \(reads)")

        let reported = try waitForEvent("the pump's bolus", since: batchesBefore) { $0.dose?.type == .bolus && $0.dose?.isMutable == false }
        XCTAssertEqual(try XCTUnwrap(reported.dose?.startDate).timeIntervalSince(pump.start), 0, accuracy: 2)
        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        XCTAssertEqual(trio.boluses.count, 1)
    }

    // MARK: - H6

    /// A bolus found in history is reported once across a relaunch, and the next one too.
    func testARelaunchReportsNoHistoryBolusTwice() throws {
        let driver = try stageDriver()
        let batchesBefore = allPumpEventBatches.count
        let first = try pumpBolus(units: 0.5)
        _ = try sync()
        _ = try waitForEvent("the first pump bolus", since: batchesBefore) { $0.dose?.type == .bolus && $0.dose?.isMutable == false }
        try waitForBackfill(driver)
        let watermark = try XCTUnwrap(driver.manager.state.historyBackfill?.watermark)

        let relaunched = try relaunch()
        XCTAssertEqual(relaunched.manager.state.historyBackfill?.watermark, watermark, "the watermark survives the relaunch")
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        let second = try pumpBolus(units: 0.7)
        _ = try sync()
        try waitForBackfill(relaunched)
        _ = try waitForEvent("the second pump bolus", since: batchesBefore) {
            $0.dose?.type == .bolus && $0.dose?.isMutable == false && $0.dose?.startDate.timeIntervalSince(second.start).magnitude ?? .infinity < 2
        }

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        XCTAssertEqual(trio.boluses.count, 2, "\(trio.boluses)")
        let starts = loop.doses.filter { $0.dose.type == .bolus }.map(\.dose.startDate)
        XCTAssertEqual(starts.count, 2, "\(loop.doses.map(LoopDoseStoreOracle.describe))")
        XCTAssertTrue(starts.contains { abs($0.timeIntervalSince(first.start)) < 2 })
    }

    // MARK: - H7

    /// The pump's log is erased and its numbering restarts below what the driver has read. The
    /// driver starts the pump's history again, and what the pump does next reaches the host once.
    func testAnErasedLogIsReadFromItsNewStart() throws {
        // The driver sees an erase only as a last record below what it has read, so the log has to
        // be longer than what the pump writes after it.
        try pumpLogs(count: 100, spacing: 300)
        let driver = try stageDriver()
        let watermark = try XCTUnwrap(driver.manager.state.historyBackfill?.watermark)
        let batchesBefore = allPumpEventBatches.count

        try harness.client.eraseHistory()
        _ = try sync()
        try IntegrationWait.until("the driver to notice the erase", timeout: 120) {
            (driver.manager.state.historyBackfill?.watermark).map { $0 < watermark } ?? true
        }

        let stoppedAt = clock.now
        _ = try harness.client.suspend(reason: "user")
        // The driver dates what it sees on its own clock, so the clock waits for it.
        try IntegrationWait.until("the driver to see the suspend", timeout: 30) { driver.manager.state.basalDose.type == .suspend }
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        let resumedAt = clock.now
        _ = try harness.client.resume(clearAlarms: true)
        _ = try sync()
        try waitForBackfill(driver)

        let suspend = try waitForEvent("the suspend", since: batchesBefore) { $0.type == .suspend }
        let resume = try waitForEvent("the resume", since: batchesBefore) { $0.type == .resume }
        XCTAssertEqual(suspend.date.timeIntervalSince(stoppedAt), 0, accuracy: 1)
        XCTAssertEqual(resume.date.timeIntervalSince(resumedAt), 0, accuracy: 1)
        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        XCTAssertEqual(trio.suspends.count, 1)
        XCTAssertEqual(trio.resumes.count, 1)
    }

    // MARK: - H8

    /// Waking from shelf mode restarts the pump's clock with no record of it; here 400 days behind.
    private static let restartedClockBehind: TimeInterval = .days(400)

    /// A pump back from shelf mode, used on its restarted clock, then set. Setup's clock change, added
    /// to the bolus from its previous use, reported it to the host as new in a field log.
    func testABolusFromBeforeShelfModeNeverReachesTheHost() throws {
        let driver = try stageDriver()
        let serial = try XCTUnwrap(driver.manager.historyLogStoreSerial)
        let batchesBefore = allPumpEventBatches.count
        try clock.advanceBoth(seconds: .hours(3), ticks: 3)
        let previousUse = try harness.client.appendHistory(records: [
            ["type": "BolusActivated", "seconds_ago": TimeInterval.days(30), "data": ["bolusId": 4400, "bolusSize": 2.0]],
            ["type": "BolusCompleted", "seconds_ago": TimeInterval.days(30) - 60, "data": [
                "completionStatusId": 3, "bolusId": 4400, "insulinDelivered": 2.0, "insulinRequested": 2.0,
            ]],
            ["type": "ShelfMode", "seconds_ago": TimeInterval.days(30) - 120, "data": [String: Any]()],
        ])
        try clock.setSkew(seconds: -Self.restartedClockBehind)
        try harness.client.appendHistory(records: [
            ["type": "BolusActivated", "seconds_ago": 3600.0, "data": ["bolusId": 4401, "bolusSize": 1.0]],
            ["type": "BolusCompleted", "seconds_ago": 3580.0, "data": [
                "completionStatusId": 3, "bolusId": 4401, "insulinDelivered": 1.0, "insulinRequested": 1.0,
            ]],
        ])
        try harness.client.setPumpTimeOnThePump(deltaSeconds: Self.restartedClockBehind)
        _ = try sync()
        try waitForBackfill(driver)

        let afterReset = try waitForEvent("the bolus after the reset", since: batchesBefore) {
            $0.raw == HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: 4401) && $0.dose?.isMutable == false
        }
        XCTAssertEqual(try XCTUnwrap(afterReset.dose?.startDate).timeIntervalSince(clock.now.addingTimeInterval(-3600)), 0, accuracy: 2)
        XCTAssertEqual(driver.manager.state.historyBackfill?.undatableThroughSequenceNum, UInt32(previousUse.upperBound))
        let previousUseRaw = HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: 4400)
        XCTAssertFalse(eventsSince(0).contains { $0.raw == previousUseRaw }, "the bolus from the pump's previous use was reported")

        let relaunched = try relaunch()
        let mark = try logMark()
        _ = try sync()
        try IntegrationWait.until("the tick to finish", timeout: 300) { !relaunched.manager.historyFetchGate.isBusy }

        let reads = try historyReads(since: mark)
        XCTAssertFalse(reads.isEmpty)
        XCTAssertTrue(reads.allSatisfy { $0.lowerBound > previousUse.upperBound }, "read at or below the ShelfMode record after a relaunch: \(reads)")
        XCTAssertFalse(eventsSince(0).contains { $0.raw == previousUseRaw }, "the bolus from the pump's previous use was reported after a relaunch")
        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        XCTAssertEqual(trio.boluses.count, 1, "\(trio.boluses)")
    }

    // MARK: - H9

    /// Eight hours on a restarted clock, then set: every record the walk reads is stamped 400 days ago.
    /// Pruned by stamp, the walk's oldest record went every hour and the walk read a slice deeper each time.
    func testAnHourlyPruneDoesNotWalkPastTheLookbackAfterAClockReset() throws {
        try stageDriver()
        try clock.advanceBoth(seconds: .hours(8), ticks: 8)
        try clock.setSkew(seconds: -Self.restartedClockBehind)
        let spacing: TimeInterval = 60
        let staged = try pumpLogs(count: Int(.hours(8) / spacing), spacing: spacing)
        try harness.client.setPumpTimeOnThePump(deltaSeconds: Self.restartedClockBehind)
        _ = try sync()
        let driver = try XCTUnwrap(current)
        try waitForBackfill(driver, timeout: 600)

        let relaunched = try relaunch()
        _ = try sync()
        try IntegrationWait.until("the walk to finish", timeout: 600) { !relaunched.manager.historyFetchGate.isBusy }
        let lowest = try XCTUnwrap(relaunched.manager.historyBackfillCoordinator.sessionCoverage?.lowerBound)
        let lookbackStart = staged.upperBound - Int(HistoryBackfillPlanner.deepFetchLookback / spacing)
        XCTAssertLessThanOrEqual(Int(lowest), lookbackStart, "the walk stopped short of the lookback by the records' stamps")

        let mark = try logMark()
        for _ in 1 ... 3 {
            try clock.advanceBoth(seconds: .hours(1) + .minutes(1), ticks: 12)
            _ = try sync()
            try IntegrationWait.until("the tick to finish", timeout: 300) { !relaunched.manager.historyFetchGate.isBusy }
        }

        let reads = try historyReads(since: mark)
        XCTAssertTrue(reads.allSatisfy { $0.lowerBound >= Int(lowest) }, "the walk went deeper after it stopped: \(reads), lowest \(lowest)")
        let serial = try XCTUnwrap(relaunched.manager.historyLogStoreSerial)
        XCTAssertNotNil(
            try relaunched.manager.historyLogStore.logs(pumpSerial: serial.rawValue, in: lowest ... lowest).first,
            "the walk's oldest record was pruned"
        )
    }

    // MARK: - H10 to H13: faketandem's clock scenarios

    private func bolusRaw(_ bolus: FaketandemScenarioResult.Bolus, _ driver: FaketandemHarness.Driver) throws -> Data {
        HistoryLogSyncIdentifier.bolus(pumpSerial: try XCTUnwrap(driver.manager.historyLogStoreSerial), bolusId: bolus.bolusId)
    }

    /// The user sets the pump's date and time on its screen to the phone's.
    private func setPumpClockRightOnThePump() throws {
        let pumpClock = try harness.client.clock()
        let wrongBy = Double(pumpClock.pumpTimezoneOffsetSeconds - TimeZone.current.secondsFromGMT(for: pumpClock.now)) + pumpClock.pumpOffsetSeconds
        try harness.client.setPumpTimeOnThePump(deltaSeconds: -wrongBy)
    }

    private func assertReportedOnceWhenGiven(
        _ bolus: FaketandemScenarioResult.Bolus,
        _ driver: FaketandemHarness.Driver,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let raw = try bolusRaw(bolus, driver)
        let reports = eventsSince(0).filter { $0.raw == raw && $0.dose?.isMutable == false }
        XCTAssertEqual(reports.count, 1, "bolus \(bolus.bolusId): \(reports.map(\.dose))", file: file, line: line)
        if let start = reports.first?.dose?.startDate {
            XCTAssertEqual(start.timeIntervalSince(bolus.start), 0, accuracy: 2, "bolus \(bolus.bolusId)", file: file, line: line)
        }
    }

    /// faketandem's `pump-reset`: a reset with no ShelfMode record restarts the clock at 2008 with no record of
    /// it. Nothing from before can be dated; the bolus on the restarted clock is, once the clock is set.
    func testOnlyTheBolusAfterAPumpResetReachesTheHostAtTheInstantItWasGiven() throws {
        let scenario = try harness.client.applyScenario(preset: "pump-reset")
        try setPumpClockRightOnThePump()
        let driver = try stageDriver(trackingSince: clock.now.addingTimeInterval(-.hours(9)))

        let afterReset = try XCTUnwrap(scenario.boluses.last)
        _ = try waitForEvent("the bolus after the reset", since: 0) { [self] in
            $0.raw == (try? bolusRaw(afterReset, driver)) && $0.dose?.isMutable == false
        }
        try assertReportedOnceWhenGiven(afterReset, driver)
        for before in scenario.boluses.dropLast() {
            let raw = try bolusRaw(before, driver)
            XCTAssertFalse(eventsSince(0).contains { $0.raw == raw }, "bolus \(before.bolusId) from before the reset was reported")
        }
        XCTAssertNotNil(driver.manager.state.historyBackfill?.undatableThroughSequenceNum, "the reset's ArmInit record is saved as the floor")
        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
    }

    /// faketandem's `out-of-shelf-mode`, the field log's pump: woken from shelf mode on a clock set to 2020. The
    /// app's write moves it 6.9 years, which carried back would date the boluses from its previous use today.
    func testNothingFromBeforeShelfModeReachesTheHostAfterTheAppSetsTheClock() throws {
        let scenario = try harness.client.applyScenario(preset: "out-of-shelf-mode")
        XCTAssertFalse(scenario.boluses.isEmpty)
        let driver = try stageDriver(trackingSince: clock.now.addingTimeInterval(-.days(1)))
        XCTAssertNoThrow(try syncPumpTime().get())
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        _ = try sync()
        try waitForBackfill(driver)

        let serial = try XCTUnwrap(driver.manager.historyLogStoreSerial)
        let doses = eventsSince(0).compactMap(\.dose).filter { $0.type == .bolus }
        XCTAssertTrue(doses.isEmpty, "\(doses)")
        for bolus in scenario.boluses {
            let raw = HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: bolus.bolusId)
            XCTAssertFalse(eventsSince(0).contains { $0.raw == raw }, "bolus \(bolus.bolusId) from before shelf mode was reported")
        }
        XCTAssertNotNil(driver.manager.state.historyBackfill?.undatableThroughSequenceNum)
    }

    /// faketandem's `clock-set-back`: the user sets the pump's clock back an hour and forward again on its
    /// screen, each change recorded, with a bolus in between stamped an hour early.
    func testBolusesAcrossAClockSetBackAndForwardOnThePumpAreReportedWhenGiven() throws {
        let scenario = try harness.client.applyScenario(preset: "clock-set-back")
        let driver = try stageDriver(trackingSince: clock.now.addingTimeInterval(-.hours(6)))
        _ = try waitForEvent("the last bolus", since: 0) { [self] in
            $0.raw == (try? bolusRaw(scenario.boluses[2], driver)) && $0.dose?.isMutable == false
        }

        for bolus in scenario.boluses {
            try assertReportedOnceWhenGiven(bolus, driver)
        }
        XCTAssertNil(driver.manager.state.historyBackfill?.undatableThroughSequenceNum, "every record is dated")
        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
    }

    /// faketandem's `reboot-kept-clock`: an ArmInit record is a reset whether or not the reboot kept the clock, so
    /// nothing before it is reported, however right its date.
    func testNothingBeforeARebootReachesTheHostEvenWhenTheRebootKeptTheClock() throws {
        let scenario = try harness.client.applyScenario(preset: "reboot-kept-clock")
        let driver = try stageDriver(trackingSince: clock.now.addingTimeInterval(-.hours(6)))
        let afterReboot = try XCTUnwrap(scenario.boluses.last)
        _ = try waitForEvent("the bolus after the reboot", since: 0) { [self] in
            $0.raw == (try? bolusRaw(afterReboot, driver)) && $0.dose?.isMutable == false
        }

        try assertReportedOnceWhenGiven(afterReboot, driver)
        for before in scenario.boluses.dropLast() {
            let raw = try bolusRaw(before, driver)
            XCTAssertFalse(eventsSince(0).contains { $0.raw == raw }, "bolus \(before.bolusId) from before the reboot was reported")
        }
        XCTAssertNotNil(driver.manager.state.historyBackfill?.undatableThroughSequenceNum, "the reboot's ArmInit record is saved as the floor")
    }
}
