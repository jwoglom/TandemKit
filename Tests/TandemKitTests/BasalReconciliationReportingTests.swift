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
        state.featureFlags[.basalHistoryReporting] = false
        state.pumpState.pumpSerial = pumpSerial
        state.bolusReportLedger = BolusReportLedger(trackingSince: .distantPast)
        state.reportedBasal = ReportedBasalLedger(trackingSince: .distantPast)
        state.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!
        state.insulinType = .novolog
        return state
    }

    private func makeManager(
        state: TandemPumpManagerState,
        archive: ReportedHistoryArchive = ReportedHistoryArchive(defaults: nil)
    ) -> TandemPumpManager {
        let manager = TandemPumpManager(state: state, bluetooth: bluetooth, reportedHistoryArchive: archive)
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
        manager.emitPumpEvents([NewPumpEvent.tempBasal(dose: dose.toDoseEntry(isMutable: true, now: at(0)), of: dose)])
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

    func testChunksFromBeforeTrackingAreCorrectedOnceSetupLoadsHistory() {
        enableReporting()
        manager.state.reportedBasal = ReportedBasalLedger(trackingSince: clock.now)
        let log = controlIQHour()
        pass(log)
        XCTAssertTrue(events.isEmpty)

        manager.state.reportedBasal.reportHistory(since: clock.now.addingTimeInterval(-TandemPumpManager.setupHistoryLoadWindow))
        pass(log)

        XCTAssertEqual(events.count, 6)
    }

    func testSetupsLoadCorrectsNothingAManagerDeletedFromThisAppReported() {
        let archive = ReportedHistoryArchive(defaults: nil)
        manager = makeManager(state: Self.state(), archive: archive)
        enableReporting()
        told([(appTemp(2.2, from: 310, id: 5), 610)])
        let log = controlIQHour()
        pass(log)
        XCTAssertEqual(events.count, 5)
        manager.archiveReportedHistory()

        var state = Self.state()
        state.reportedBasal = ReportedBasalLedger(trackingSince: clock.now)
        manager = makeManager(state: state, archive: archive)
        setupBatches = 0
        enableReporting()
        manager.inheritArchivedReports()
        manager.state.reportedBasal.reportHistory(since: clock.now.addingTimeInterval(-TandemPumpManager.setupHistoryLoadWindow))
        pass(log)

        XCTAssertTrue(events.isEmpty)
    }

    func testConsecutiveCyclesAtOneRateAreEachCorrected() {
        enableReporting()
        var log = PumpBasalHistory()
        log.pcm(0, .closedLoop)
        for cycle in 0 ..< 4 {
            log.delivery(10 + cycle * 300, source: 3, rate: 2200)
        }

        pass(log)

        XCTAssertEqual(events.map(\.date), (0 ..< 4).map { at(Double(10 + $0 * 300)) })
        XCTAssertEqual(events.map { $0.dose?.endDate }, (1 ... 4).map { at(Double(10 + $0 * 300)) })
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

    /// #353 G07: Control-IQ turned on at the pump ends the app's temp, which the driver still holds.
    func testAnAppTempHeldWhenControlIQStartsOnThePumpEndsAtItsCompletion() throws {
        enableReporting()
        holdTemp(percent: 150, id: 5)
        manager.state.useControlIQ = true
        var log = PumpBasalHistory()
        log.tempStarted(0, percent: 150, minutes: 30, id: 5)
        log.delivery(10, source: 2, rate: 1500)
        log.tempEnded(200, id: 5, timeLeft: 1_600_000)
        log.pcm(200, .closedLoop)
        log.delivery(310, source: 3, rate: 2200)
        log.delivery(610, source: 3, rate: 400)

        pass(log)

        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches.first?.replacePendingEvents, true)
        let ended = try XCTUnwrap(events.first?.dose)
        XCTAssertEqual(ended.endDate, at(200))
        XCTAssertFalse(ended.isMutable)
        let corrections = events.filter { HistoryLogSyncIdentifier.decode($0.raw)?.scheme == .logSequence }
        XCTAssertEqual(corrections.map(\.date), [at(310), at(610)])
        XCTAssertTrue(corrections.allSatisfy { $0.dose?.automatic == true })
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

    func testAPumpTempWhoseStartIsLostInAStoreGapIsCorrectedOnceTheGapIsGivenUp() {
        enableReporting()
        var log = PumpBasalHistory()
        log.profile(10)
        log.tempStarted(100, percent: 150, minutes: 30, id: 7)
        log.delivery(310, source: 2, rate: 1500)
        log.delivery(610, source: 2, rate: 1500)
        log.profile(910)
        log.lose(1002)

        pass(log)
        pass(log)
        XCTAssertTrue(events.isEmpty, "held back by the gap")
        pass(log)

        XCTAssertEqual(events.map(\.date), [at(310), at(610)])
        XCTAssertEqual(events.map { $0.dose?.unitsPerHour }, [1.5, 1.5])
    }

    func testAFailingRecordIsLoggedOnceASession() {
        var log = PumpBasalHistory()
        log.pcm(0, .openLoop)
        let failing = log.delivery(10, source: 3, rate: 2200)

        pass(log)
        pass(log)

        XCTAssertEqual(manager.loggedBasalProblems, [failing])
    }

    func testAFailingRecordReconciliationIsDoneWithIsNotLogged() {
        enableReporting()
        var log = PumpBasalHistory()
        log.pcm(0, .openLoop)
        let failing = log.delivery(10, source: 3, rate: 2200)
        manager.state.reportedBasal.track(pumpSerial: Self.pumpSerial, after: failing)

        pass(log)

        XCTAssertTrue(manager.loggedBasalProblems.isEmpty)
    }

    // MARK: - A change just after a BasalDelivery record

    /// The app's stop reached the pump just before the BasalDelivery record at 310 and its 0% temp
    /// just after, so the pump ran its profile until the record at 610.
    private func stopRacingTheNextTemp() -> PumpBasalHistory {
        var log = PumpBasalHistory()
        log.tempStarted(0, percent: 116, minutes: 30, id: 5)
        log.delivery(10, source: 2, rate: 1160)
        log.tempEnded(309, id: 5, timeLeft: 1_501_000)
        log.profile(310)
        log.tempStarted(311, percent: 0, minutes: 30, id: 6)
        log.delivery(610, source: 2, rate: 0)
        return log
    }

    private func appTemp(_ rate: Double, from start: TimeInterval, to end: TimeInterval? = nil, id: Int) -> UnfinalizedDose {
        UnfinalizedDose(
            tempRate: rate,
            duration: .minutes(30),
            automatic: true,
            insulinType: .novolog,
            startDate: at(start),
            tempRateId: id,
            tempPercent: Int((rate * 100).rounded())
        )
    }

    private func told(_ temps: [(dose: UnfinalizedDose, end: TimeInterval?)], markerAt marker: TimeInterval? = nil) {
        var events = temps.map { dose, end in
            NewPumpEvent.tempBasal(dose: dose.toDoseEntry(isMutable: end == nil, endDate: end.map(at), now: at(end ?? 0)), of: dose)
        }
        if let marker {
            let dose = UnfinalizedDose(basalRate: 1, insulinType: .novolog, startDate: at(marker))
            events.append(NewPumpEvent.basal(dose: dose.toDoseEntry(), date: at(marker)))
        }
        manager.emitPumpEvents(events, replacePendingEvents: false)
        delegateQueue.sync {}
        setupBatches = delegate.pumpEventBatches.count
    }

    /// #564
    func testACycleTheNextFinishedTempMissedIsCorrectedOverThatTemp() {
        enableReporting()
        told([(appTemp(1.16, from: 0, id: 5), 310.5), (appTemp(0, from: 310.5, id: 6), 621)], markerAt: 621)
        var log = stopRacingTheNextTemp()
        log.tempEnded(621, id: 6, timeLeft: 1_489_000)
        log.profile(910)
        log.profile(1210)

        pass(log)

        XCTAssertEqual(events.map(\.date), [at(311.5), at(610)])
        XCTAssertEqual(events.map { $0.dose?.endDate }, [at(610), at(621)])
        XCTAssertEqual(events.map { $0.dose?.unitsPerHour }, [1.0, 0])
        XCTAssertEqual(events.first?.dose?.deliveredUnits, 0.083)

        pass(log)
        XCTAssertEqual(events.count, 2, "a second pass reports nothing")
    }

    func testACycleTheHeldTempMissedIsRestatedForThatCycleOnly() {
        enableReporting()
        let held = appTemp(0, from: 310.5, id: 6)
        manager.state.basalDose = held
        told([(appTemp(1.16, from: 0, id: 5), 310.5), (held, nil)])
        var log = stopRacingTheNextTemp()

        pass(log)

        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches.first?.replacePendingEvents, true)
        let temps = events.compactMap(\.dose).filter { $0.type == .tempBasal }
        XCTAssertEqual(temps.map(\.startDate), [at(310.5), at(311.5), at(610)])
        XCTAssertEqual(temps.map(\.endDate), [at(311.5), at(610), at(2110.5)])
        XCTAssertEqual(temps.map(\.unitsPerHour), [0, 1.0, 0])
        XCTAssertEqual(temps.map(\.isMutable), [false, false, true])
        XCTAssertEqual(manager.state.basalDose.startDate, at(610))
        XCTAssertEqual(manager.state.basalDose.value, 0)
        XCTAssertEqual(manager.state.basalDose.tempRateId, 6)

        log.delivery(910, source: 2, rate: 0)
        pass(log)
        XCTAssertEqual(batches.count, 1, "the held temp runs at its own rate again")
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

    // MARK: - Over a finalized temp basal

    /// The host told of a temp basal at `rate` U/hr from `start` to `end` seconds, finished, and the
    /// schedule after it.
    private func toldFinishedTemp(_ rate: Double, from start: TimeInterval, to end: TimeInterval) {
        let dose = UnfinalizedDose(tempRate: rate, duration: .minutes(30), automatic: true, insulinType: .novolog, startDate: at(start))
        let entry = dose.toDoseEntry(isMutable: false, endDate: at(end), now: at(end))
        let marker = UnfinalizedDose(basalRate: 1, insulinType: .novolog, startDate: at(end))
        manager.emitPumpEvents([
            NewPumpEvent.tempBasal(dose: entry, of: dose),
            NewPumpEvent.basal(dose: marker.toDoseEntry(), date: at(end))
        ], replacePendingEvents: false)
        delegateQueue.sync {}
        setupBatches = delegate.pumpEventBatches.count
    }

    func testAFinishedTempThePumpEndedEarlierIsReportedOverFromItsDifference() throws {
        enableReporting()
        toldFinishedTemp(1.5, from: 0, to: 900)
        var log = PumpBasalHistory()
        log.tempStarted(0, percent: 150, minutes: 15, id: 6)
        log.delivery(10, source: 2, rate: 1500)
        log.delivery(310, source: 2, rate: 1500)
        log.tempEnded(500, id: 6, timeLeft: 400_000)
        log.profile(610)
        log.profile(910)

        pass(log)

        XCTAssertEqual(events.count, 1)
        let correction = try XCTUnwrap(events.first?.dose)
        XCTAssertEqual(correction.startDate, at(610))
        XCTAssertEqual(correction.endDate, at(900), "through the finished temp basal's end")
        XCTAssertEqual(correction.unitsPerHour, 1.0)

        pass(log)
        XCTAssertEqual(events.count, 1, "a second pass reports nothing")
    }

    func testOverAFinishedTempEveryChunkThroughItsEndIsReported() {
        enableReporting()
        toldFinishedTemp(1.5, from: 10, to: 910)
        var log = PumpBasalHistory()
        log.delivery(10, source: 3, rate: 2200)
        log.delivery(310, source: 3, rate: 1500)
        log.delivery(610, source: 3, rate: 400)
        log.delivery(910, source: 3, rate: 1000)

        pass(log)

        XCTAssertEqual(events.map(\.date), [at(11), at(310), at(610)], "the first a second after the temp basal it replaces")
        XCTAssertEqual(events.map { $0.dose?.unitsPerHour }, [2.2, 1.5, 0.4])
        XCTAssertEqual(events.last?.dose?.endDate, at(910))
    }

    func testOverAFinishedTempNothingIsReportedUntilItsChunksAreAllRead() {
        enableReporting()
        toldFinishedTemp(1.5, from: 10, to: 910)
        clock.set(at(700))
        var log = PumpBasalHistory()
        log.delivery(10, source: 3, rate: 2200)
        log.delivery(310, source: 3, rate: 1500)
        log.delivery(610, source: 3, rate: 400)

        pass(log)

        XCTAssertTrue(events.isEmpty)
    }
}
