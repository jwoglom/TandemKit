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

    @discardableResult
    private func stageDriver(backfill: Bool = true, doseReporting: Bool = true) throws -> FaketandemHarness.Driver {
        try harness.client.setState(["basal_rate": Self.profileRate])
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.historyBackfill] = backfill
        state.featureFlags[.historyDoseReporting] = doseReporting
        state.bolusReportLedger = BolusReportLedger(trackingSince: clock.now)
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

        let log = try harness.requestLog(since: mark).filter(\.isRequest)
        let bolusAt = try XCTUnwrap(log.firstIndex { $0.message == "InitiateBolusRequest" }, "the bolus never went out")
        let readsBefore = log[..<bolusAt].filter { $0.message == "HistoryLogRequest" }.count
        let readsAfter = log[bolusAt...].filter { $0.message == "HistoryLogRequest" }.count
        XCTAssertGreaterThan(readsAfter, 0, "the bolus waited for the whole walk (\(readsBefore) reads before it)")
        XCTAssertLessThanOrEqual(readsBefore, 3, "the bolus waited for more than the slice in flight")
        try IntegrationWait.until("the walk to finish", timeout: 900) {
            try self.missingFromSessionStore(relaunched, staged.upperBound - 1000 ... staged.upperBound).isEmpty
        }
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
}
