import LoopKit
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class ReconciliationLogTests: XCTestCase {
    private static let pumpSerial: UInt32 = 654_321

    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var clock: ManualClock!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        clock = ManualClock(PumpBasalHistory.date(7200))
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.historyBackfill] = true
        state.featureFlags[.basalHistoryReporting] = false
        state.pumpState.pumpSerial = Self.pumpSerial
        state.bolusReportLedger = BolusReportLedger(trackingSince: .distantPast)
        state.reportedBasal = ReportedBasalLedger(trackingSince: .distantPast)
        state.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!
        state.insulinType = .novolog
        manager = TandemPumpManager(state: state, bluetooth: bluetooth)
        manager.clock = clock
        delegate = MockPumpManagerDelegate()
        manager.pumpManagerDelegate = delegate
        manager.waitForDelegateCalls()
    }

    override func tearDown() {
        manager = nil
        delegate = nil
        bluetooth = nil
        super.tearDown()
    }

    private func pass(_ log: PumpBasalHistory) {
        manager.storeHistoryLogs(log.logs, now: clock.now)
        let sequences = log.logs.map(\.sequenceNum)
        let range = sequences.min()! ... sequences.max()!
        manager.reportHistoryDoses(after: outcome(range), now: clock.now)
        manager.waitForDelegateCalls()
    }

    private func outcome(_ range: ClosedRange<UInt32>) -> HistoryBackfillCoordinator.TickOutcome {
        HistoryBackfillCoordinator.TickOutcome(
            bookkeeping: HistoryBackfillState(pumpSerial: Self.pumpSerial, watermark: range.upperBound),
            rangesRead: [range],
            sessionCovered: range,
            isDeepBackfillComplete: true,
            emitFloor: .distantPast,
            startedAt: clock.now,
            pumpSequenceRange: range
        )
    }

    /// Control-IQ alternates 1.0 and 2.2 U/hr against a 1.0 U/hr schedule, so every other cycle differs.
    private func controlIQHour() -> PumpBasalHistory {
        var log = PumpBasalHistory()
        log.pcm(0, .closedLoop)
        for cycle in 0 ..< 12 {
            log.delivery(10 + cycle * 300, source: 3, rate: cycle.isMultiple(of: 2) ? 1000 : 2200)
        }
        return log
    }

    func testAPassRecordsItsSpanAndBasalCountsAndEachDifferenceAsLeftByReportingOff() throws {
        let log = controlIQHour()

        pass(log)

        let recorded = manager.reconciliationLog
        XCTAssertEqual(recorded.passes.count, 1)
        let pass = try XCTUnwrap(recorded.passes.last)
        XCTAssertEqual(pass.covered, 1001 ... 1013)
        XCTAssertTrue(pass.readsThroughPumpEnd)
        XCTAssertNil(pass.skipped)
        XCTAssertEqual(pass.basal?.matched, 6)
        XCTAssertEqual(pass.basal?.differed, 6)
        XCTAssertEqual(pass.basal?.corrections, 0)
        XCTAssertNil(pass.basal?.heldBack)
        XCTAssertEqual(pass.transitionsReported, 0)
        XCTAssertEqual(recorded.differences.count, 6)
        XCTAssertEqual(Set(recorded.differences.map(\.outcome)), [.reportingOff])
        XCTAssertEqual(recorded.differences.first?.pumpRate, 2.2)
        XCTAssertEqual(recorded.differences.first?.hostRate, 1.0)
        XCTAssertEqual(recorded.differences.first?.hostSource, .schedule)
        XCTAssertEqual(recorded.differences.first?.pumpKind, .algorithm)
        XCTAssertEqual(recorded.residualDays.map(\.cycles), [6])
    }

    func testWithReportingOnEachDifferenceIsCorrectedAndThePassCountsIt() throws {
        manager.state.featureFlags[.basalHistoryReporting] = true

        pass(controlIQHour())

        let recorded = manager.reconciliationLog
        XCTAssertEqual(Set(recorded.differences.map(\.outcome)), [.corrected])
        XCTAssertEqual(recorded.passes.last?.basal?.corrections, 6)
        XCTAssertEqual(recorded.passes.last?.basal?.reconciledThrough, 1013)
    }

    func testASecondPassOverTheSameHistoryReplacesNothingAndAddsAPass() {
        let log = controlIQHour()

        pass(log)
        pass(log)

        XCTAssertEqual(manager.reconciliationLog.passes.count, 2)
        XCTAssertEqual(manager.reconciliationLog.differences.count, 6)
    }

    func testAnUntrustedRecordIsADifferenceLeftUntrustedAndAProblem() {
        manager.state.featureFlags[.basalHistoryReporting] = true
        var log = PumpBasalHistory()
        log.pcm(0, .openLoop)
        let failing = log.delivery(10, source: 3, rate: 2200)
        log.delivery(310, source: 1, rate: 1000)

        pass(log)

        let recorded = manager.reconciliationLog
        XCTAssertEqual(recorded.differences.map(\.outcome), [.untrusted])
        XCTAssertEqual(recorded.problems.map(\.sequenceNum), [failing])
        XCTAssertTrue(recorded.problems[0].description.contains("BasalDelivery #\(failing)"))
    }

    func testAStoreGapIsRecordedAsWhatHeldThePassBack() {
        manager.state.featureFlags[.basalHistoryReporting] = true
        var log = PumpBasalHistory()
        log.delivery(10, source: 3, rate: 2200)
        log.other(100)
        log.delivery(310, source: 3, rate: 2200)
        log.other(400)
        log.delivery(610, source: 3, rate: 2200)
        log.lose(1004)

        pass(log)

        XCTAssertEqual(manager.reconciliationLog.passes.last?.basal?.heldBack, .storeGap(1004 ... 1004))
        XCTAssertEqual(manager.reconciliationLog.differences.map(\.outcome), [.corrected])
    }

    func testATickThatCouldNotReadThePumpIsASkippedPass() {
        manager.historyTickFailed(startedAt: clock.now)

        XCTAssertEqual(manager.reconciliationLog.passes.count, 1)
        XCTAssertEqual(manager.reconciliationLog.passes.last?.skipped, "Pump history could not be read")
        XCTAssertNil(manager.reconciliationLog.passes.last?.basal)
    }

    func testNothingIsRecordedWithoutTheBackfill() {
        manager.state.featureFlags[.historyBackfill] = false

        pass(controlIQHour())

        XCTAssertTrue(manager.reconciliationLog.passes.isEmpty)
        XCTAssertTrue(manager.reconciliationLog.differences.isEmpty)
    }

    // MARK: - Bounds

    private func difference(_ sequenceNum: UInt32) -> ReconciliationLog.Difference {
        ReconciliationLog.Difference(
            sequenceNum: sequenceNum,
            start: PumpBasalHistory.date(Int(sequenceNum) * 300),
            end: PumpBasalHistory.date(Int(sequenceNum) * 300 + 300),
            pumpKind: .temp,
            pumpRate: 0.5,
            hostRate: 1.0,
            hostSource: .schedule,
            outcome: .waiting,
            noticedAt: clock.now
        )
    }

    func testTheLogKeepsTheNewestEntriesAndReplacesAChunkComparedAgain() {
        var log = ReconciliationLog()
        for sequenceNum in 1 ... UInt32(ReconciliationLog.differenceLimit + 10) {
            log.record(difference(sequenceNum))
        }
        XCTAssertEqual(log.differences.count, ReconciliationLog.differenceLimit)
        XCTAssertEqual(log.differences.first?.sequenceNum, 11)

        var again = difference(60)
        again.outcome = .corrected
        log.record(again)
        XCTAssertEqual(log.differences.count, ReconciliationLog.differenceLimit)
        XCTAssertEqual(log.differences.last?.outcome, .corrected)

        for pass in 0 ..< ReconciliationLog.passLimit + 5 {
            log.recordSkippedPass(startedAt: clock.now.addingTimeInterval(TimeInterval(pass)), reason: "test", at: clock.now)
        }
        XCTAssertEqual(log.passes.count, ReconciliationLog.passLimit)
        XCTAssertEqual(log.passes.first?.startedAt, clock.now.addingTimeInterval(5))
    }

    func testADifferenceGivesTheInsulinTheHostCountsOverThePump() {
        XCTAssertEqual(difference(1).units, 0.5 * 300 / 3600, accuracy: 0.0001)
    }
}
