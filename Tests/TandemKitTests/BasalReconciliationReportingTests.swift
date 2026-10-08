import LoopKit
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class BasalReconciliationReportingTests: XCTestCase {
    private static let pumpSerial: UInt32 = 654_321
    private let serial = HistoryLogSyncIdentifier.PumpSerial(BasalReconciliationReportingTests.pumpSerial)!

    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!
    private var clock: ManualClock!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        clock = ManualClock(PumpBasalHistory.date(7200))
        manager = makeManager(state: Self.state())
    }

    override func tearDown() {
        manager = nil
        delegate = nil
        delegateQueue = nil
        bluetooth = nil
        super.tearDown()
    }

    private static func state() -> TandemPumpManagerState {
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.historyBackfill] = true
        state.pumpState.pumpSerial = pumpSerial
        state.bolusReportLedger = BolusReportLedger(trackingSince: .distantPast)
        state.reportedBasal = ReportedBasalLedger(trackingSince: .distantPast)
        state.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!
        state.insulinType = .novolog
        return state
    }

    private func makeManager(state: TandemPumpManagerState) -> TandemPumpManager {
        let manager = TandemPumpManager(state: state, bluetooth: bluetooth)
        manager.clock = clock
        delegate = MockPumpManagerDelegate()
        delegateQueue = DispatchQueue(label: "basal-reconciliation-reporting-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}
        return manager
    }

    private func pass(_ log: PumpBasalHistory) {
        manager.storeHistoryLogs(log.logs, now: clock.now)
        let sequences = log.logs.map(\.sequenceNum)
        let range = sequences.min()! ... sequences.max()!
        manager.reportHistoryDoses(
            after: HistoryBackfillCoordinator.TickOutcome(
                bookkeeping: HistoryBackfillState(pumpSerial: Self.pumpSerial, watermark: range.upperBound),
                rangesRead: [range],
                sessionCovered: range,
                isDeepBackfillComplete: true,
                emitFloor: .distantPast,
                startedAt: clock.now,
                pumpSequenceRange: range
            ),
            now: clock.now
        )
        delegateQueue.sync {}
    }

    private func controlIQHour() -> PumpBasalHistory {
        var log = PumpBasalHistory()
        log.pcm(0, .closedLoop)
        for cycle in 0 ..< 12 {
            log.delivery(10 + cycle * 300, source: 3, rate: cycle.isMultiple(of: 2) ? 1000 : 2200)
        }
        return log
    }

    func testDifferencesAreLoggedOnceAndNothingIsReported() {
        let log = controlIQHour()

        pass(log)
        XCTAssertEqual(manager.loggedBasalDifferences.count, 6)
        pass(log)

        XCTAssertEqual(manager.loggedBasalDifferences.count, 6)
        XCTAssertTrue(delegate.pumpEventBatches.flatMap(\.events).isEmpty)
    }

    func testNothingIsComparedWithoutTheBackfill() {
        manager.state.featureFlags[.historyBackfill] = false

        pass(controlIQHour())

        XCTAssertTrue(manager.loggedBasalDifferences.isEmpty)
    }

    // MARK: - Reporting

    private func enableReporting() {
        manager.state.featureFlags[.basalHistoryReporting] = true
    }

    /// Batches before this many are setup.
    private var setupBatches = 0

    private var batches: [MockPumpManagerDelegate.PumpEventBatch] {
        Array(delegate.pumpEventBatches.dropFirst(setupBatches))
    }

    private var events: [NewPumpEvent] {
        batches.flatMap(\.events)
    }

    private func at(_ seconds: TimeInterval) -> Date {
        PumpBasalHistory.date(0).addingTimeInterval(seconds)
    }

    /// The host told of an app temp basal at `percent` of 1 U/hr from `date(0)`.
    private func holdTemp(percent: Int, id: Int) {
        let dose = UnfinalizedDose(
            tempRate: Double(percent) / 100,
            duration: .minutes(30),
            automatic: true,
            insulinType: .novolog,
            startDate: at(0),
            tempRateId: id,
            tempPercent: percent
        )
        manager.state.basalDose = dose
        manager.emitPumpEvents([NewPumpEvent.tempBasal(dose: dose.toDoseEntry(isMutable: true, now: at(0)), date: at(0))])
        delegateQueue.sync {}
        setupBatches = delegate.pumpEventBatches.count
    }

    func testCorrectionsGoOutOnceAscendingImmutableAndAtThePumpsRate() throws {
        enableReporting()
        let log = controlIQHour()

        pass(log)

        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches.first?.replacePendingEvents, false)
        let corrections = events
        XCTAssertEqual(corrections.map(\.date), (0 ..< 6).map { at(Double(310 + $0 * 600)) })
        let deliveries = log.logs.compactMap { $0 as? BasalDeliveryHistoryLog }
        for (correction, delivery) in zip(corrections, deliveries.filter { $0.commandedRate == 2200 }) {
            let dose = try XCTUnwrap(correction.dose)
            XCTAssertEqual(dose.type, .tempBasal)
            XCTAssertFalse(dose.isMutable)
            XCTAssertEqual(dose.unitsPerHour, 2.2)
            XCTAssertEqual(dose.endDate.timeIntervalSince(dose.startDate), 300)
            XCTAssertEqual(dose.deliveredUnits, 0.183)
            XCTAssertEqual(dose.automatic, true)
            XCTAssertTrue(dose.wasProgrammedByPumpUI)
            XCTAssertEqual(correction.title, "Control-IQ Basal")
            XCTAssertEqual(correction.raw, HistoryLogSyncIdentifier.logSequence(pumpSerial: serial, sequenceNum: delivery.sequenceNum))
        }

        pass(log)
        XCTAssertEqual(events.count, 6, "a second pass reports nothing")
    }

    func testNothingIsReportedTwiceAcrossARelaunch() {
        enableReporting()
        let log = controlIQHour()
        pass(log)
        XCTAssertEqual(events.count, 6)

        manager = makeManager(state: TandemPumpManagerState(rawValue: manager.state.rawValue))
        pass(log)

        XCTAssertTrue(events.isEmpty)
    }

    func testTheTransitionsPassAndTheCorrectionsGoOutInOneBatch() {
        enableReporting()
        manager.state.deliveryTransitions.track(pumpSerial: Self.pumpSerial, after: 1000)
        var log = PumpBasalHistory()
        log.delivery(10, source: 3, rate: 1000)
        log.suspended(100)
        log.resumed(200)
        log.delivery(310, source: 3, rate: 2200)

        pass(log)

        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(events.map(\.type), [.suspend, .resume, .tempBasal])
        XCTAssertEqual(events.last?.date, at(310))
    }

    func testAHeldTempThePumpEndedIsEndedAtItsCompletion() throws {
        enableReporting()
        holdTemp(percent: 150, id: 5)
        var log = PumpBasalHistory()
        log.tempStarted(0, percent: 150, minutes: 30, id: 5)
        log.delivery(10, source: 2, rate: 1500)
        log.tempEnded(200, id: 5, timeLeft: 1_600_000)
        log.delivery(310, source: 3, rate: 2200)

        pass(log)

        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches.first?.replacePendingEvents, true)
        XCTAssertEqual(events.map(\.type), [.tempBasal, .basal, .tempBasal])
        let ended = try XCTUnwrap(events.first?.dose)
        XCTAssertFalse(ended.isMutable)
        XCTAssertEqual(ended.endDate, at(200))
        XCTAssertEqual(events[1].date, at(200))
        XCTAssertEqual(events[2].date, at(310))
        XCTAssertEqual(manager.state.basalDose.type, .basal)
    }

    func testAHeldTempThePumpRunsAtAnotherRateIsRestated() throws {
        enableReporting()
        holdTemp(percent: 150, id: 5)
        var log = PumpBasalHistory()
        log.tempStarted(0, percent: 150, minutes: 30, id: 5)
        log.delivery(10, source: 2, rate: 1800, profile: 1200)
        log.delivery(310, source: 2, rate: 1800, profile: 1200)

        pass(log)

        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches.first?.replacePendingEvents, true)
        XCTAssertFalse(events.contains { $0.type == .basal }, "no marker between the two parts")
        let finished = try XCTUnwrap(events.first { $0.dose?.isMutable == false }?.dose)
        XCTAssertEqual(finished.startDate, at(0))
        XCTAssertEqual(finished.endDate, at(10))
        XCTAssertEqual(finished.unitsPerHour, 1.5)
        let running = try XCTUnwrap(events.first { $0.dose?.isMutable == true }?.dose)
        XCTAssertEqual(running.startDate, at(10))
        XCTAssertEqual(running.unitsPerHour, 1.8)
        XCTAssertEqual(manager.state.basalDose.value, 1.8)
        XCTAssertEqual(manager.state.basalDose.tempRateId, 5)
    }

    func testACorrectionAfterAHeldTempWaitsForItsCompletion() {
        enableReporting()
        holdTemp(percent: 150, id: 5)
        var log = PumpBasalHistory()
        log.tempStarted(0, percent: 150, minutes: 30, id: 5)
        log.delivery(10, source: 2, rate: 1500)
        // The pump ran the temp out unseen; its completion is not in the store yet.
        log.delivery(1810, source: 3, rate: 2200)

        pass(log)

        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(manager.state.basalDose.type, .tempBasal)
    }

    func testACorrectionNeverStartsInTheSecondOfAHostRow() throws {
        enableReporting()
        manager.emitPumpEvents([NewPumpEvent.basal(
            dose: UnfinalizedDose(basalRate: 1, insulinType: .novolog, startDate: at(310)).toDoseEntry(),
            date: at(310)
        )])
        delegateQueue.sync {}
        setupBatches = delegate.pumpEventBatches.count
        var log = PumpBasalHistory()
        log.delivery(10, source: 3, rate: 1000)
        log.delivery(310, source: 3, rate: 2200)

        pass(log)

        let correction = try XCTUnwrap(events.first?.dose)
        XCTAssertEqual(correction.startDate, at(311))
        XCTAssertEqual(correction.endDate, at(610))
    }

    func testAnUntrustedChunkIsNotCorrected() {
        enableReporting()
        var log = PumpBasalHistory()
        log.pcm(0, .openLoop)
        log.delivery(10, source: 3, rate: 2200)

        pass(log)

        XCTAssertTrue(events.isEmpty)
    }

    func testAStoreGapHoldsReportingBackForTwoPasses() {
        enableReporting()
        var log = PumpBasalHistory()
        log.delivery(10, source: 3, rate: 2200)
        log.other(100)
        log.delivery(310, source: 3, rate: 2200)
        log.other(400)
        log.delivery(610, source: 3, rate: 2200)
        log.lose(1004)

        pass(log)
        XCTAssertEqual(events.map(\.date), [at(10)], "the chunk after the gap waits")
        pass(log)
        XCTAssertEqual(events.count, 1)
        pass(log)
        XCTAssertEqual(events.map(\.date), [at(10), at(610)], "given up: past it, skipping the chunk it held open")
    }

    // MARK: - Control-IQ hand-back

    func testAControlIQEndIsAwaitedOnlyWithReporting() {
        manager.state.controlIQEndedAt = at(3000)
        XCTAssertFalse(manager.isAwaitingHistory)

        enableReporting()
        XCTAssertTrue(manager.isAwaitingHistory)
    }

    func testAControlIQEndPastTheReportingHorizonIsNotAwaited() {
        enableReporting()
        manager.state.controlIQEndedAt = clock.now.addingTimeInterval(-BolusReportLedger.reportingHorizon - 60)

        XCTAssertFalse(manager.isAwaitingHistory)
    }

    func testAPassThatReadPastTheControlIQEndReleasesTheSync() {
        enableReporting()
        manager.state.controlIQEndedAt = at(3000)
        let released = expectation(description: "the sync waiting on history completes")
        manager.afterHistoryIsReported { released.fulfill() }

        pass(controlIQHour())

        wait(for: [released], timeout: 5)
        XCTAssertNil(manager.state.controlIQEndedAt)
        XCTAssertEqual(events.count, 6)
    }

    func testAPassThatStartedBeforeTheControlIQEndDoesNotClearIt() {
        enableReporting()
        manager.state.controlIQEndedAt = clock.now.addingTimeInterval(60)

        pass(controlIQHour())

        XCTAssertNotNil(manager.state.controlIQEndedAt)
    }

    func testTheHandBackWaitTimesOut() {
        enableReporting()
        manager.transitionHistoryWait = .milliseconds(50)
        manager.state.controlIQEndedAt = at(3000)
        let released = expectation(description: "the sync completes without history")
        manager.afterHistoryIsReported { released.fulfill() }

        wait(for: [released], timeout: 5)
        XCTAssertNotNil(manager.state.controlIQEndedAt, "the corrections go out with a later pass")
    }

    func testASyncIsNotThrottledWhileTheHandBackIsAwaited() {
        enableReporting()
        manager.state.isConnected = true
        manager.state.lastReconciliation = clock.now
        manager.state.controlIQEndedAt = at(3000)
        manager.transitionHistoryWait = .milliseconds(50)
        let synced = expectation(description: "the sync completes")

        manager.ensureCurrentPumpData { _ in synced.fulfill() }

        wait(for: [synced], timeout: 10)
        XCTAssertGreaterThan(bluetooth.ensureConnectedCount, 0)
    }

    func testControlIQSeenInHistoryWhileOffReadsItsStatus() {
        pass(controlIQHour())

        XCTAssertTrue(bluetooth.sentMessages.contains { String(describing: type(of: $0)).hasPrefix("ControlIQInfo") })
    }
}
