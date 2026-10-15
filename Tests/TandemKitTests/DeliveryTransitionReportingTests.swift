import LoopKit
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class DeliveryTransitionReportingTests: XCTestCase {
    private static let pumpSerial: UInt32 = 123_456
    private let serial = HistoryLogSyncIdentifier.PumpSerial(DeliveryTransitionReportingTests.pumpSerial)!
    private static let scheduledRate = 1.0
    private static let firstSequenceNum: UInt32 = 1000

    private var bluetooth: StubPumpBluetooth!
    private var clock: ManualClock!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!

    /// Whole seconds: pump timestamps are.
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var nextSequenceNum = DeliveryTransitionReportingTests.firstSequenceNum

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        clock = ManualClock(start)
        manager = makeManager(state: Self.backfillState(start: start))
    }

    override func tearDown() {
        manager = nil
        delegate = nil
        delegateQueue = nil
        clock = nil
        bluetooth = nil
        super.tearDown()
    }

    private static func backfillState(start: Date) -> TandemPumpManagerState {
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.historyBackfill] = true
        state.pumpState.pumpSerial = pumpSerial
        state.insulinType = .novolog
        state.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: scheduledRate)])!
        state.basalDose = UnfinalizedDose(basalRate: scheduledRate, insulinType: .novolog, startDate: start)
        state.hasSyncedBasalRateSchedule = true
        // Watching the pump since before the records these tests write.
        state.deliveryTransitions = DeliveryTransitionLedger(pumpSerial: pumpSerial, trackedAfter: firstSequenceNum - 1)
        return state
    }

    private func makeManager(state: TandemPumpManagerState) -> TandemPumpManager {
        let manager = TandemPumpManager(state: state, bluetooth: bluetooth, clock: clock)
        delegate = MockPumpManagerDelegate()
        delegate.journalClock = clock
        delegateQueue = DispatchQueue(label: "delivery-transition-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}
        return manager
    }

    // MARK: - Driving the pump

    private func minutes(_ minutes: Double) -> Date {
        start.addingTimeInterval(minutes * 60)
    }

    private func advance(to date: Date) {
        clock.set(date)
    }

    /// `basalModifiedBitmask` 0 is scheduled basal, 1 suspended, 2 a temp rate.
    private func stubBasalStatus(_ bitmask: Int) {
        bluetooth.stub(CurrentBasalStatusRequest.self, with: CurrentBasalStatusResponse(
            profileBasalRate: 1000,
            currentBasalRate: bitmask == 1 ? 0 : 1000,
            basalModifiedBitmask: bitmask
        ))
    }

    private func observe(_ bitmask: Int) {
        stubBasalStatus(bitmask)
        manager.fetchBasalStatus()
        delegateQueue.sync {}
    }

    private func pumpTimeSec(_ date: Date, pumpAhead offset: TimeInterval = 0) -> UInt32 {
        UInt32(Dates.fromInstantToJan12008EpochSeconds(date.addingTimeInterval(offset)))
    }

    private func takeSequenceNum() -> UInt32 {
        defer { nextSequenceNum += 1 }
        return nextSequenceNum
    }

    private func suspended(at date: Date, pumpAhead offset: TimeInterval = 0) -> HistoryLog {
        PumpingSuspendedHistoryLog(
            pumpTimeSec: pumpTimeSec(date, pumpAhead: offset),
            sequenceNum: takeSequenceNum(),
            preSuspendState: 106,
            insulinAmount: 100,
            reasonId: 1,
            rpaTimeout: 15
        )
    }

    private func resumed(at date: Date) -> HistoryLog {
        PumpingResumedHistoryLog(pumpTimeSec: pumpTimeSec(date), sequenceNum: takeSequenceNum(), preResumeState: 100, insulinAmount: 100)
    }

    /// `timeLeft` is the seconds of its programmed duration still to run; 0 once it ran out.
    private func tempRateCompleted(_ tempRateId: Int, at date: Date, timeLeft: UInt32) -> HistoryLog {
        TempRateCompletedHistoryLog(pumpTimeSec: pumpTimeSec(date), sequenceNum: takeSequenceNum(), tempRateId: tempRateId, timeLeft: timeLeft)
    }

    private func storedSequenceNums() -> [UInt32] {
        (try? manager.historyLogStore.logs(pumpSerial: Self.pumpSerial, in: 0 ... UInt32.max))?.map(\.sequenceNum) ?? []
    }

    /// Stores `logs` and runs the history pass as a tick that started at `startedAt` (default now)
    /// and read the whole store, of a pump whose log ends at `pumpLast` if given.
    private func pass(
        _ logs: [HistoryLog],
        startedAt: Date? = nil,
        pumpLast: UInt32? = nil,
        reachesBack: Bool = true
    ) {
        manager.storeHistoryLogs(logs, now: clock.now)
        let sequences = storedSequenceNums()
        guard let first = sequences.min(), let last = sequences.max() else { return }
        let batch = manager.reportHistoryDeliveryTransitions(
            after: HistoryBackfillCoordinator.TickOutcome(
                bookkeeping: HistoryBackfillState(pumpSerial: Self.pumpSerial, watermark: last),
                rangesRead: [first ... last],
                sessionCovered: first ... last,
                isDeepBackfillComplete: reachesBack,
                emitFloor: .distantPast,
                startedAt: startedAt ?? clock.now,
                pumpSequenceRange: (reachesBack ? first : first - 1) ... max(last, pumpLast ?? last)
            ),
            pumpSerial: serial
        )
        manager.emitHistoryReports(batch)
        delegateQueue.sync {}
    }

    private var batches: [MockPumpManagerDelegate.PumpEventBatch] { delegate.pumpEventBatches }

    private var events: [NewPumpEvent] { batches.flatMap(\.events) }

    private func events(_ type: DoseType) -> [NewPumpEvent] {
        events.filter { $0.dose?.type == type }
    }

    private var transitions: [DoseType?] {
        events.map(\.dose?.type).filter { $0 == .suspend || $0 == .resume }
    }

    private func appSuspend() {
        bluetooth.stub(TempRateRequest.self, with: TempRateResponse(active: false, percentage: 0, startTimeRaw: 0, duration: 0))
        bluetooth.stub(SuspendPumpingRequest.self, with: SuspendPumpingResponse(status: 0))
        let done = expectation(description: "suspendDelivery")
        manager.suspendDelivery { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        delegateQueue.sync {}
    }

    private func appResume() {
        bluetooth.stub(ResumePumpingRequest.self, with: ResumePumpingResponse(status: 0))
        let done = expectation(description: "resumeDelivery")
        manager.resumeDelivery { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        wait(for: [done], timeout: 60)
        delegateQueue.sync {}
    }

    private func appTempBasal(_ rate: Double) {
        bluetooth.stubBasalPump(profileMilliunits: UInt32(Self.scheduledRate * 1000), tempRateId: 50)
        let done = expectation(description: "enactTempBasal")
        manager.enactTempBasal(unitsPerHour: rate, for: .minutes(30)) { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        delegateQueue.sync {}
    }

    private func runningTempBasal(_ rate: Double, tempRateId: Int? = 7, percent: Int? = nil, from startDate: Date? = nil) {
        manager.state.basalDose = UnfinalizedDose(
            tempRate: rate,
            duration: .minutes(30),
            automatic: true,
            insulinType: .novolog,
            startDate: startDate ?? start,
            tempRateId: tempRateId,
            tempPercent: percent
        )
    }

    private func tempRateActivated(_ tempRateId: Int, at date: Date, percent: Float, minutes: Float = 30) -> HistoryLog {
        TempRateActivatedHistoryLog(
            pumpTimeSec: pumpTimeSec(date),
            sequenceNum: takeSequenceNum(),
            percent: percent,
            durationMilliseconds: minutes * 60000,
            tempRateId: tempRateId
        )
    }

    private func setOverBluetooth(_ tempRateId: Int, at date: Date) -> HistoryLog {
        SetTempRateResponseHistoryLog(pumpTimeSec: pumpTimeSec(date), sequenceNum: takeSequenceNum(), status: 0, unknown11: 0, tempRateId: tempRateId)
    }

    /// A reading of a temp at `percent` of the pump's 1 U/hr, which the pump started at `pumpStart`.
    private func observeTemp(percent: Int, from pumpStart: Date) {
        bluetooth.stub(TempRateRequest.self, with: TempRateResponse(
            active: true,
            percentage: percent,
            startTimeRaw: pumpTimeSec(pumpStart),
            duration: 0
        ))
        observe(2)
    }

    // MARK: - Dated from history

    func testASuspendDuringAnOutageIsReportedAtThePumpsTimeNotAtDetection() throws {
        advance(to: minutes(30))
        observe(1)

        XCTAssertTrue(batches.isEmpty, "nothing is reported at detection: \(events)")
        XCTAssertEqual(manager.state.basalDose.type, .suspend, "status shows the pump suspended straight away")
        XCTAssertNotNil(manager.state.deliveryTransitions.pending)

        pass([suspended(at: minutes(10))])

        let suspend = try XCTUnwrap(events(.suspend).first)
        XCTAssertEqual(events(.suspend).count, 1)
        XCTAssertEqual(suspend.date, minutes(10))
        XCTAssertEqual(suspend.dose?.startDate, minutes(10))
        XCTAssertEqual(suspend.dose?.isMutable, false)
        XCTAssertEqual(manager.state.basalDose.type, .suspend)
        XCTAssertEqual(manager.state.basalDose.startDate, minutes(10))
        XCTAssertNil(manager.state.deliveryTransitions.pending)
    }

    func testASuspendAndResumeBothInsideAnOutageAreReportedAsAPair() {
        observe(0)
        advance(to: minutes(30))
        observe(0)
        XCTAssertNil(manager.state.deliveryTransitions.pending, "the pump looks unchanged to the live path")

        pass([suspended(at: minutes(5)), resumed(at: minutes(15))])

        XCTAssertEqual(events.map(\.dose?.type), [.suspend, .resume])
        XCTAssertEqual(events.map(\.date), [minutes(5), minutes(15)])
        XCTAssertEqual(batches.last?.replacePendingEvents, false, "nothing the host holds open is being finished")
        XCTAssertEqual(manager.state.basalDose.type, .basal)
    }

    func testAResumeDuringAnOutageAfterAnAppSuspendIsReportedAsAResume() throws {
        appSuspend()
        let appSuspendReport = try XCTUnwrap(events(.suspend).first)
        let suspendRecord = suspended(at: start.addingTimeInterval(1))

        advance(to: minutes(30))
        observe(0)
        XCTAssertEqual(events(.suspend).count, 1, "only the app's own suspend so far")
        XCTAssertTrue(events(.basal).isEmpty, "no scheduled-basal marker in place of the resume (#331)")

        pass([suspendRecord, resumed(at: minutes(12))])

        XCTAssertEqual(events(.suspend), [appSuspendReport], "the app's suspend is not reported again from history")
        XCTAssertEqual(events(.resume).map(\.date), [minutes(12)])
        XCTAssertEqual(manager.state.basalDose.type, .resume)
        XCTAssertEqual(manager.state.basalDose.startDate, minutes(12))
    }

    func testATempBasalStoppedByAnOutageSuspendEndsAtItsCompletion() throws {
        runningTempBasal(2.0)
        advance(to: minutes(20))
        observe(1)
        XCTAssertTrue(batches.isEmpty)

        pass([tempRateCompleted(7, at: minutes(8), timeLeft: 22 * 60), suspended(at: minutes(8))])

        let batch = try XCTUnwrap(batches.last)
        XCTAssertTrue(batch.replacePendingEvents, "the temp basal the host holds open is finished in the same batch")
        let temp = try XCTUnwrap(batch.events.first { $0.dose?.type == .tempBasal })
        XCTAssertEqual(temp.dose?.isMutable, false)
        XCTAssertEqual(temp.dose?.startDate, start)
        XCTAssertEqual(temp.dose?.endDate, minutes(8), "ended when the pump stopped it, not at reconnect")
        XCTAssertEqual(try XCTUnwrap(temp.dose?.deliveredUnits), 2.0 * 8 / 60, accuracy: 0.0005)
        XCTAssertEqual(batch.events.first { $0.dose?.type == .suspend }?.date, minutes(8))
        XCTAssertEqual(manager.state.basalDose.type, .suspend)
    }

    func testATempBasalWithNoRateIdEndsAtTheSuspendInsideTheGap() {
        runningTempBasal(2.0, tempRateId: nil)
        advance(to: minutes(20))
        observe(1)

        pass([suspended(at: minutes(8))])

        XCTAssertEqual(events(.tempBasal).first?.dose?.endDate, minutes(8))
        XCTAssertEqual(events(.suspend).map(\.date), [minutes(8)])
    }

    func testATempBasalThatRanOutDuringAnOutageEndsAtItsScheduledEnd() {
        runningTempBasal(2.0, tempRateId: 8)
        advance(to: minutes(50))
        observe(0)

        pass([tempRateCompleted(8, at: minutes(30), timeLeft: 0)])

        XCTAssertEqual(events(.tempBasal).first?.dose?.endDate, minutes(30))
        XCTAssertEqual(events(.basal).first?.date, minutes(30), "scheduled basal resumes at the temp basal's end")
        XCTAssertTrue(transitions.isEmpty)
        XCTAssertEqual(manager.state.basalDose.type, .basal)
    }

    func testATempBasalThatRanOutIsFinishedUnderTheIdentityItWasReportedUnder() throws {
        runningTempBasal(2.0, tempRateId: 8)
        let reported = NewPumpEvent.tempBasal(dose: manager.state.basalDose.toDoseEntry(isMutable: true), of: manager.state.basalDose)
        advance(to: minutes(50))
        observe(0)

        pass([tempRateCompleted(8, at: minutes(30).addingTimeInterval(-1), timeLeft: 0)])

        let finished = try XCTUnwrap(events(.tempBasal).first)
        XCTAssertEqual(finished.dose?.endDate, minutes(30))
        XCTAssertEqual(finished.raw, reported.raw)
    }

    func testATempBasalWhoseRecordSaysItRanOutButIsDatedEarlyEndsAtTheRecord() {
        runningTempBasal(2.0, tempRateId: 8)
        advance(to: minutes(50))
        observe(0)

        pass([tempRateCompleted(8, at: minutes(20), timeLeft: 0)])

        XCTAssertEqual(events(.tempBasal).first?.dose?.endDate, minutes(20), "the record's date wins over a timeLeft it contradicts")
    }

    func testATempBasalEndedByASuspendAndResumeInsideAnOutageIsFinishedWithThePair() throws {
        runningTempBasal(2.0, tempRateId: 9)
        advance(to: minutes(40))
        observe(0)

        pass([tempRateCompleted(9, at: minutes(10), timeLeft: 20 * 60), suspended(at: minutes(10)), resumed(at: minutes(20))])

        let batch = try XCTUnwrap(batches.last)
        XCTAssertEqual(batch.events.map(\.dose?.type), [.tempBasal, .suspend, .resume])
        XCTAssertEqual(batch.events.first?.dose?.endDate, minutes(10))
        XCTAssertTrue(batch.replacePendingEvents)
        XCTAssertEqual(manager.state.basalDose.type, .resume)
        XCTAssertEqual(manager.state.basalDose.startDate, minutes(20))
    }

    func testHistoryTimesAreMovedOntoThePhonesClock() {
        manager.state.currentPumpTime = minutes(0).addingTimeInterval(120)
        manager.state.lastPumpTimeCheckDate = minutes(0)
        advance(to: minutes(30))
        observe(1)

        pass([suspended(at: minutes(10), pumpAhead: 120)])

        XCTAssertEqual(events(.suspend).first?.date, minutes(10))
    }

    // MARK: - Waiting for history

    func testNothingIsReportedByATickThatStartedBeforeTheChangeWasSeen() {
        advance(to: minutes(30))
        observe(1)

        pass([suspended(at: minutes(10))], startedAt: minutes(29))

        XCTAssertTrue(batches.isEmpty)
        XCTAssertNotNil(manager.state.deliveryTransitions.pending)
    }

    func testATickThatDidNotReadToThePumpsLastRecordReportsTheChangeAtDetection() {
        advance(to: minutes(30))
        observe(1)

        pass([suspended(at: minutes(10))], pumpLast: Self.firstSequenceNum + 5)

        XCTAssertEqual(events(.suspend).map(\.date), [minutes(30)], "a later record could be the one that dates it")
        XCTAssertNil(manager.state.deliveryTransitions.pending)
    }

    func testATickWhoseStoreDoesNotReachBackToTheLastReadingReportsTheChangeAtDetection() {
        observe(0)
        advance(to: minutes(30))
        observe(1)

        pass([suspended(at: minutes(10))], reachesBack: false)

        XCTAssertEqual(events(.suspend).map(\.date), [minutes(30)], "a record before the store's first could be the one that dates it")
        XCTAssertNil(manager.state.deliveryTransitions.pending)
    }

    func testAPendingChangeSurvivesARelaunch() {
        advance(to: minutes(30))
        observe(1)

        manager = makeManager(state: TandemPumpManagerState(rawValue: manager.state.rawValue))
        XCTAssertEqual(manager.state.basalDose.type, .suspend)
        pass([suspended(at: minutes(10))])

        XCTAssertEqual(events(.suspend).map(\.date), [minutes(10)])
    }

    // MARK: - A temp the pump runs in place of the held one (#340)

    func testATempThePumpRunsInPlaceOfTheHeldOneIsAdoptedFromHistory() throws {
        runningTempBasal(1.5, percent: 150)
        advance(to: minutes(12))
        observeTemp(percent: 120, from: minutes(5))
        XCTAssertTrue(batches.isEmpty)
        XCTAssertTrue(manager.isAwaitingHistory, "the sync waits for history")

        pass([
            tempRateCompleted(7, at: minutes(5), timeLeft: 25 * 60),
            tempRateActivated(8, at: minutes(5), percent: 120),
            setOverBluetooth(8, at: minutes(5))
        ])

        let batch = try XCTUnwrap(batches.last)
        XCTAssertTrue(batch.replacePendingEvents)
        let temps = batch.events.compactMap(\.dose).filter { $0.type == .tempBasal }
        XCTAssertEqual(temps.map(\.startDate), [start, minutes(5)])
        XCTAssertEqual(temps.first?.endDate, minutes(5), "the held temp ends at its completion")
        XCTAssertEqual(temps.first?.isMutable, false)
        XCTAssertEqual(temps.last?.unitsPerHour, 1.2)
        XCTAssertEqual(temps.last?.isMutable, true)
        XCTAssertEqual(temps.last?.endDate, minutes(35), "for the duration the pump recorded")
        XCTAssertEqual(temps.last?.automatic, true, "set over Bluetooth")
        XCTAssertEqual(batch.events.last { $0.dose?.type == .tempBasal }?.raw, HistoryLogSyncIdentifier.tempRate(pumpSerial: serial, tempRateId: 8))
        XCTAssertFalse(batch.events.contains { $0.dose?.type == .basal })
        XCTAssertEqual(manager.state.basalDose.tempRateId, 8)
        XCTAssertEqual(manager.state.basalDose.tempPercent, 120)
        XCTAssertNil(manager.state.deliveryTransitions.pending)
    }

    func testATempSetOnThePumpInPlaceOfTheHeldOneIsNotAutomatic() {
        runningTempBasal(1.5, percent: 150)
        advance(to: minutes(12))
        observeTemp(percent: 120, from: minutes(5))

        pass([tempRateCompleted(7, at: minutes(5), timeLeft: 25 * 60), tempRateActivated(8, at: minutes(5), percent: 120)])

        XCTAssertEqual(events(.tempBasal).last?.dose?.automatic, false)
    }

    func testAReplacingTempThatHasRunOutIsReportedFinished() throws {
        runningTempBasal(1.5, percent: 150)
        advance(to: minutes(12))
        observeTemp(percent: 120, from: minutes(5))
        advance(to: minutes(40))

        pass([
            tempRateCompleted(7, at: minutes(5), timeLeft: 25 * 60),
            tempRateActivated(8, at: minutes(5), percent: 120),
            tempRateCompleted(8, at: minutes(35), timeLeft: 0)
        ])

        let replacing = try XCTUnwrap(events(.tempBasal).last?.dose)
        XCTAssertEqual(replacing.startDate, minutes(5))
        XCTAssertEqual(replacing.endDate, minutes(35))
        XCTAssertFalse(replacing.isMutable)
        XCTAssertEqual(events(.basal).map(\.date), [minutes(35)])
        XCTAssertEqual(manager.state.basalDose.type, .basal)
    }

    func testTheHeldTempIsNotTakenForAReplacement() {
        runningTempBasal(1.5, percent: 150)
        advance(to: minutes(12))
        observeTemp(percent: 150, from: start.addingTimeInterval(2))

        XCTAssertNil(manager.state.deliveryTransitions.pending)
    }

    func testAHeldTempCutAtASegmentChangeIsNotTakenForAReplacement() {
        // The running part of a temp cut at a change starts there, after the pump's record of its start.
        runningTempBasal(1.5, percent: 150, from: minutes(10))
        advance(to: minutes(12))
        observeTemp(percent: 150, from: start)

        XCTAssertNil(manager.state.deliveryTransitions.pending)
    }

    func testAReplacementHistoryShowsToBeTheHeldTempIsDropped() {
        runningTempBasal(1.5, tempRateId: 7, percent: 150)
        advance(to: minutes(12))
        // The pump's clock puts the held temp's start three minutes late.
        observeTemp(percent: 150, from: minutes(3))
        XCTAssertNotNil(manager.state.deliveryTransitions.pending)

        pass([tempRateActivated(7, at: minutes(3), percent: 150)])

        XCTAssertTrue(batches.isEmpty)
        XCTAssertNil(manager.state.deliveryTransitions.pending)
        XCTAssertEqual(manager.state.basalDose.tempRateId, 7)
    }

    func testAReplacementHistoryDoesNotCoverIsReportedAtDetection() throws {
        runningTempBasal(1.5, percent: 150)
        advance(to: minutes(12))
        observeTemp(percent: 120, from: minutes(5))
        advance(to: minutes(13))

        pass([tempRateCompleted(7, at: minutes(5), timeLeft: 25 * 60)], pumpLast: nextSequenceNum + 5)

        let temps = events(.tempBasal).compactMap(\.dose)
        XCTAssertEqual(temps.first?.endDate, minutes(5), "the held temp ends at the pump's record of the new one's start")
        let replacing = try XCTUnwrap(temps.last)
        XCTAssertEqual(replacing.startDate, minutes(5))
        XCTAssertEqual(replacing.unitsPerHour, 1.2)
        XCTAssertEqual(replacing.endDate, minutes(12), "above the schedule, at the last reading that saw it")
        XCTAssertFalse(replacing.isMutable)
        XCTAssertEqual(events(.basal).map(\.date), [minutes(12)])
    }

    func testAReplacementBelowTheScheduleIsReportedAtDetectionUntilTheFirstReadingThatSawIt() throws {
        runningTempBasal(1.5, percent: 150)
        advance(to: minutes(12))
        observeTemp(percent: 50, from: minutes(5))
        advance(to: minutes(17))
        observeTemp(percent: 50, from: minutes(5))

        manager.historyTickFailed(startedAt: minutes(17))
        delegateQueue.sync {}

        XCTAssertEqual(events(.tempBasal).last?.dose?.endDate, minutes(12))
    }

    func testAnAppTempWhileAReplacementIsPendingReportsItFirstAndNotInTheCommandsSecond() throws {
        runningTempBasal(1.5, percent: 150)
        advance(to: minutes(12))
        observeTemp(percent: 120, from: minutes(5))
        advance(to: minutes(14))

        bluetooth.stubBasalPump(profileMilliunits: 1000, runningTempPercent: 120, tempRateId: 50)
        let done = expectation(description: "enactTempBasal")
        manager.enactTempBasal(unitsPerHour: 2.0, for: .minutes(30)) { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        delegateQueue.sync {}

        let temps = events(.tempBasal).compactMap(\.dose)
        XCTAssertEqual(temps.map(\.startDate), [start, minutes(5), minutes(14)])
        XCTAssertEqual(temps[1].endDate, minutes(14), "the command's own reading saw it running")
        XCTAssertTrue(events(.basal).isEmpty, "nothing in the second the app's temp starts")
    }

    func testAPendingReplacementSurvivesARelaunch() {
        runningTempBasal(1.5, percent: 150)
        advance(to: minutes(12))
        observeTemp(percent: 120, from: minutes(5))

        manager = makeManager(state: TandemPumpManagerState(rawValue: manager.state.rawValue))
        pass([tempRateCompleted(7, at: minutes(5), timeLeft: 25 * 60), tempRateActivated(8, at: minutes(5), percent: 120)])

        XCTAssertEqual(manager.state.basalDose.tempRateId, 8)
        XCTAssertEqual(manager.state.basalDose.value, 1.2)
    }

    func testWithTheFlagOffTheTempRateIsNotRead() {
        manager.state.featureFlags[.historyBackfill] = false
        runningTempBasal(1.5, percent: 150)
        advance(to: minutes(12))

        observeTemp(percent: 120, from: minutes(5))

        XCTAssertFalse(bluetooth.didSend(TempRateRequest.self))
        XCTAssertNil(manager.state.deliveryTransitions.pending)
    }

    // MARK: - Reported at detection

    func testASecondChangeBeforeHistoryDatesTheFirstReportsTheFirstAtDetection() {
        advance(to: minutes(30))
        observe(1)
        advance(to: minutes(40))
        observe(0)

        XCTAssertEqual(events(.suspend).map(\.date), [minutes(30)], "the latest the pump can have stopped")
        XCTAssertNotNil(manager.state.deliveryTransitions.pending, "the resume is left for history")

        pass([suspended(at: minutes(10)), resumed(at: minutes(35))])

        XCTAssertEqual(transitions, [.suspend, .resume], "the stop's record matches the report, and the resume goes out once")
        XCTAssertEqual(events(.resume).map(\.date), [minutes(35)])
        XCTAssertEqual(manager.state.basalDose.type, .resume)
    }

    func testAChangeWhoseRecordPredatesTrackingIsReportedAtDetection() {
        manager.state.deliveryTransitions = DeliveryTransitionLedger(pumpSerial: Self.pumpSerial, trackedAfter: Self.firstSequenceNum)
        advance(to: minutes(30))
        observe(1)

        pass([suspended(at: minutes(10))])

        XCTAssertEqual(events(.suspend).map(\.date), [minutes(30)], "a record from before tracking may have been reported without an entry")
    }

    func testAResumeWithNoRecordIsReportedAtTheLastReadingThatSawTheSuspend() {
        appSuspend()
        let appRecord = suspended(at: start.addingTimeInterval(1))
        advance(to: minutes(5))
        observe(1)
        advance(to: minutes(30))
        observe(0)

        pass([appRecord])

        XCTAssertEqual(events(.resume).map(\.date), [minutes(5)], "the earliest the pump can have resumed, which counts more insulin")
    }

    func testWithTheFlagOffASuspendIsReportedAtDetection() throws {
        manager.state.featureFlags[.historyBackfill] = false
        advance(to: minutes(30))
        observe(1)

        XCTAssertEqual(events(.suspend).map(\.date), [minutes(30)])
        let entry = try XCTUnwrap(manager.state.deliveryTransitions.entries.first)
        XCTAssertEqual(entry.earliest, start.addingTimeInterval(-TandemPumpManager.transitionMatchTolerance), "its pump record can be anywhere since the last reading")
        XCTAssertEqual(entry.latest, minutes(30).addingTimeInterval(TandemPumpManager.transitionMatchTolerance))
    }

    func testWithTheFlagOffAPumpSideResumeIsReportedAsAResume() {
        manager.state.featureFlags[.historyBackfill] = false
        appSuspend()
        advance(to: minutes(5))
        observe(1)
        advance(to: minutes(30))
        observe(0)

        XCTAssertEqual(events(.resume).map(\.date), [minutes(5)], "a resume, not a scheduled-basal marker (#331), at the last reading that saw the suspend")
        XCTAssertTrue(events(.basal).isEmpty)
        XCTAssertEqual(manager.state.basalDose.type, .resume)
    }

    func testWithTheFlagOffAResumeIntoATempRateIsReportedAsAResume() {
        manager.state.featureFlags[.historyBackfill] = false
        appSuspend()
        advance(to: minutes(30))
        observe(2)

        XCTAssertEqual(events(.resume).count, 1)
        XCTAssertEqual(manager.state.basalDose.type, .resume)
    }

    func testWithTheFlagOffATempBasalAboveTheScheduleEndsAtDetection() {
        manager.state.featureFlags[.historyBackfill] = false
        runningTempBasal(2.0)
        advance(to: minutes(10))
        observe(2)
        advance(to: minutes(20))
        observe(0)

        XCTAssertEqual(events(.tempBasal).first?.dose?.endDate, minutes(20), "the latest it can have ended, which counts more insulin")
        XCTAssertEqual(events(.basal).first?.date, minutes(20))
    }

    func testWithTheFlagOffATempBasalBelowTheScheduleEndsAtTheLastReading() {
        manager.state.featureFlags[.historyBackfill] = false
        runningTempBasal(0.5)
        advance(to: minutes(10))
        observe(2)
        advance(to: minutes(20))
        observe(0)

        XCTAssertEqual(events(.tempBasal).first?.dose?.endDate, minutes(10), "the earliest it can have ended, which counts more insulin")
        XCTAssertEqual(events(.basal).first?.date, minutes(10))
    }

    func testTurningTheFlagOffReportsAPendingChangeAtTheNextReading() {
        advance(to: minutes(30))
        observe(1)
        manager.state.featureFlags[.historyBackfill] = false

        advance(to: minutes(31))
        observe(1)

        XCTAssertEqual(events(.suspend).map(\.date), [minutes(30)])
        XCTAssertNil(manager.state.deliveryTransitions.pending)
    }

    // MARK: - App commands go out after the change

    func testAnAppTempBasalWhileAResumeIsPendingReportsTheResumeFirst() {
        appSuspend()
        advance(to: minutes(5))
        observe(1)
        advance(to: minutes(30))
        observe(0)
        let before = batches.count

        appTempBasal(2.0)

        let after = Array(batches.dropFirst(before)).flatMap(\.events)
        XCTAssertEqual(after.map(\.dose?.type), [.resume, .tempBasal], "Loop closes an open suspend at the temp basal for good (#354)")
        XCTAssertEqual(after.first?.date, minutes(5))
        XCTAssertNil(manager.state.deliveryTransitions.pending)
        XCTAssertEqual(manager.state.basalDose.type, .tempBasal)
    }

    func testAnAppResumeWhileASuspendIsPendingReportsTheSuspendFirst() {
        advance(to: minutes(30))
        observe(1)

        appResume()

        XCTAssertEqual(transitions, [.suspend, .resume], "Trio takes a resume with no suspend before it as suspended since its history began")
        XCTAssertEqual(events(.suspend).first?.date, minutes(30))
        XCTAssertEqual(events(.resume).first?.date, minutes(30).addingTimeInterval(1), "Trio's IOB throws on a suspend and resume in one second")
        XCTAssertEqual(manager.state.basalDose.type, .resume)
    }

    func testAnAppSuspendWhileAResumeIsPendingReportsTheResumeFirst() {
        appSuspend()
        advance(to: minutes(5))
        observe(1)
        advance(to: minutes(30))
        observe(0)

        appSuspend()

        XCTAssertEqual(transitions, [.suspend, .resume, .suspend])
        XCTAssertEqual(events(.resume).map(\.date), [minutes(5)])
        XCTAssertEqual(events(.suspend).last?.date, minutes(30))
    }

    func testThePumpsRecordOfAChangeReportedBeforeACommandIsNotReportedAgain() {
        appSuspend()
        let suspendRecord = suspended(at: start.addingTimeInterval(1))
        advance(to: minutes(5))
        observe(1)
        advance(to: minutes(30))
        observe(0)
        appTempBasal(2.0)
        let reported = events.count

        pass([suspendRecord, resumed(at: minutes(12))])

        XCTAssertEqual(events.count, reported)
    }

    func testAnAppTempBasalFinishesTheOneThePumpEndedAtTheLastReadingThatSawIt() throws {
        runningTempBasal(0.5)
        advance(to: minutes(10))
        observe(2)
        advance(to: minutes(20))

        appTempBasal(2.0)

        let finished = try XCTUnwrap(events(.tempBasal).first { $0.dose?.isMutable == false })
        XCTAssertEqual(finished.dose?.endDate, minutes(10), "a temp basal below the schedule is ended as early as it can have ended")
        XCTAssertEqual(events(.tempBasal).last?.dose?.isMutable, true, "then the new one")
        XCTAssertFalse(bluetooth.didSend(StopTempRateRequest.self), "the pump was not running one to stop")
    }

    // MARK: - The sync waits for history

    /// Serves `logs` the way the pump does: status from their range, entries streamed back on
    /// `historyLogStream` after the request is acknowledged.
    private func stubPump(serving logs: [HistoryLog], streams: Bool = true) {
        let bySequence = Dictionary(uniqueKeysWithValues: logs.map { ($0.sequenceNum, $0) })
        let sequences = logs.map(\.sequenceNum)
        bluetooth.stub(HistoryLogStatusRequest.self, with: HistoryLogStatusResponse(
            numEntries: UInt32(logs.count),
            firstSequenceNum: sequences.min()!,
            lastSequenceNum: sequences.max()!
        ))
        bluetooth.stub(HistoryLogRequest.self, with: HistoryLogResponse(status: 0, streamId: 7))
        guard streams else { return }
        bluetooth.onWrite = { [weak self] message in
            guard let self, let request = message as? HistoryLogRequest else { return }
            let top = request.startLog
            let bottom = top >= UInt32(max(request.numberOfLogs, 1)) ? top - UInt32(max(request.numberOfLogs, 1)) + 1 : 0
            let streamed = stride(from: top, through: bottom, by: -1).compactMap { bySequence[$0] }
            guard !streamed.isEmpty else { return }
            self.manager.historyLogStream.send(HistoryLogStreamResponse(
                numberOfHistoryLogs: streamed.count,
                streamId: 7,
                historyLogStreamBytes: streamed.map(\.cargo)
            ))
        }
    }

    private func sync() {
        let synced = expectation(description: "syncPumpData")
        manager.syncPumpData { _ in synced.fulfill() }
        wait(for: [synced], timeout: 60)
        delegateQueue.sync {}
    }

    func testASyncThatSeesAChangeCompletesOnceHistoryHasDatedIt() {
        stubPump(serving: [resumed(at: start.addingTimeInterval(-60)), suspended(at: minutes(10))])
        advance(to: minutes(30))
        stubBasalStatus(1)

        sync()

        XCTAssertEqual(events(.suspend).map(\.date), [minutes(10)], "reported before the host is told the sync is done")
        XCTAssertTrue(events(.resume).isEmpty, "the resume before the outage had no suspend to close")
        XCTAssertNil(manager.state.deliveryTransitions.pending)
    }

    func testASyncThatEndsWhileAnEarlierTickRunsWaitsForTheTickAfterIt() {
        stubPump(serving: [resumed(at: start.addingTimeInterval(-60)), suspended(at: minutes(10))])
        advance(to: minutes(29))
        manager.historyBackfillCoordinator.runTick()
        advance(to: minutes(30))
        stubBasalStatus(1)

        sync()

        XCTAssertEqual(events(.suspend).map(\.date), [minutes(10)], "the running tick started before the change was seen; the one after it dates it")
        XCTAssertNil(manager.state.deliveryTransitions.pending)
    }

    func testASyncWhoseHistoryCannotBeReadReportsTheChangeAtDetection() {
        advance(to: minutes(30))
        stubBasalStatus(1)

        sync()

        XCTAssertEqual(events(.suspend).map(\.date), [minutes(30)])
        XCTAssertNil(manager.state.deliveryTransitions.pending)
    }

    func testASyncWhoseHistoryIsSlowReportsTheChangeAtDetectionOnceTheWaitIsOver() {
        manager.transitionHistoryWait = .milliseconds(300)
        stubPump(serving: [suspended(at: minutes(10))], streams: false)
        advance(to: minutes(30))
        stubBasalStatus(1)

        sync()

        XCTAssertEqual(events(.suspend).map(\.date), [minutes(30)])
        XCTAssertNil(manager.state.deliveryTransitions.pending)
    }

    func testASyncThatSeesNoChangeDoesNotWaitForHistory() {
        // A pump that can bolus on its own waits for history anyway.
        manager.state.quickBolusEnabled = false
        stubPump(serving: [suspended(at: minutes(10))], streams: false)
        stubBasalStatus(0)

        let began = Date()
        sync()

        XCTAssertLessThan(Date().timeIntervalSince(began), 1, "the tick runs on after the sync")
    }

    private func fetchSuspendStatus() -> Bool? {
        let done = expectation(description: "fetchSuspendStatus")
        var answer: Bool?
        manager.fetchSuspendStatus { isSuspended in
            answer = isSuspended
            done.fulfill()
        }
        wait(for: [done], timeout: 60)
        delegateQueue.sync {}
        return answer
    }

    func testTheSuspendAWizardFindsIsReportedFromHistoryBeforeItAnswers() {
        stubPump(serving: [resumed(at: start.addingTimeInterval(-60)), suspended(at: minutes(10))])
        advance(to: minutes(30))
        stubBasalStatus(1)

        XCTAssertEqual(fetchSuspendStatus(), true)

        XCTAssertEqual(events(.suspend).map(\.date), [minutes(10)], "the wizard resumes next; the host must hold the suspend first (#348)")
        XCTAssertNil(manager.state.deliveryTransitions.pending)
    }

    func testWithTheFlagOffTheSuspendAWizardFindsIsReportedAtDetection() {
        manager.state.featureFlags[.historyBackfill] = false
        advance(to: minutes(30))
        stubBasalStatus(1)

        XCTAssertEqual(fetchSuspendStatus(), true)

        XCTAssertEqual(events(.suspend).map(\.date), [minutes(30)])
    }

    // MARK: - Resume reads the pump first

    func testResumeReportsAMissedStopFromHistoryFirst() {
        stubPump(serving: [resumed(at: start.addingTimeInterval(-60)), suspended(at: minutes(10))])
        advance(to: minutes(30))
        stubBasalStatus(1)

        appResume()

        XCTAssertEqual(transitions, [.suspend, .resume], "Trio takes a resume with no suspend before it as suspended since its history began")
        XCTAssertEqual(events(.suspend).map(\.date), [minutes(10)])
        XCTAssertEqual(events(.resume).map(\.date), [minutes(30)])
        XCTAssertEqual(manager.state.basalDose.type, .resume)
        XCTAssertNil(manager.state.deliveryTransitions.pending)
    }

    func testResumeEndsTheTempBasalWhereThePumpStoppedIt() {
        runningTempBasal(1.5)
        stubPump(serving: [
            resumed(at: start.addingTimeInterval(-60)),
            tempRateCompleted(7, at: minutes(10), timeLeft: 1200),
            suspended(at: minutes(10))
        ])
        advance(to: minutes(30))
        stubBasalStatus(1)

        appResume()

        let finished = events(.tempBasal).filter { $0.dose?.isMutable == false }
        XCTAssertEqual(finished.map(\.dose?.endDate), [minutes(10)], "finished once, at the pump's stop, and not again by the resume")
        XCTAssertEqual(transitions, [.suspend, .resume])
        XCTAssertEqual(events(.suspend).map(\.date), [minutes(10)])
        XCTAssertEqual(events(.resume).map(\.date), [minutes(30)])
    }

    func testWithTheFlagOffResumeReportsAMissedStopAtDetectionFirst() {
        manager.state.featureFlags[.historyBackfill] = false
        advance(to: minutes(30))
        stubBasalStatus(1)

        appResume()

        XCTAssertEqual(transitions, [.suspend, .resume])
        XCTAssertEqual(events(.suspend).map(\.date), [minutes(30)])
        XCTAssertEqual(events(.resume).map(\.date), [minutes(30).addingTimeInterval(1)], "Trio's IOB throws on a suspend and resume in one second")
    }

    func testResumeReportsAMissedStopAtDetectionWhenHistoryIsSlow() {
        manager.transitionHistoryWait = .milliseconds(300)
        stubPump(serving: [suspended(at: minutes(10))], streams: false)
        advance(to: minutes(30))
        stubBasalStatus(1)

        appResume()

        XCTAssertEqual(transitions, [.suspend, .resume])
        XCTAssertEqual(events(.suspend).map(\.date), [minutes(30)])
    }

    func testResumeAfterAnAppSuspendDoesNotWaitForHistory() {
        appSuspend()
        advance(to: minutes(30))
        stubBasalStatus(1)

        appResume()

        XCTAssertEqual(transitions, [.suspend, .resume])
        XCTAssertFalse(bluetooth.didSend(HistoryLogStatusRequest.self), "the pump is suspended, as the host was told")
    }

    func testResumeStillResumesWhenTheBasalStatusReadFails() {
        advance(to: minutes(30))

        appResume()

        XCTAssertEqual(bluetooth.sent(CurrentBasalStatusRequest.self).count, 1)
        XCTAssertTrue(bluetooth.didSend(ResumePumpingRequest.self))
        XCTAssertEqual(events(.resume).map(\.date), [minutes(30)])
    }

    func testEnsureCurrentPumpDataSyncsWhileAChangeIsPending() {
        advance(to: minutes(30))
        observe(1)
        manager.state.lastReconciliation = minutes(30)
        let reads = bluetooth.sent(CurrentBasalStatusRequest.self).count

        let done = expectation(description: "ensureCurrentPumpData")
        manager.ensureCurrentPumpData { _ in done.fulfill() }
        wait(for: [done], timeout: 60)

        XCTAssertGreaterThan(bluetooth.sent(CurrentBasalStatusRequest.self).count, reads, "not throttled while the host has not been told")
        XCTAssertNil(manager.state.deliveryTransitions.pending)
    }

    // MARK: - Seen at an alarm

    private func handleQualifyingEvents(_ events: Set<QualifyingEvent>) {
        let acknowledged = expectation(description: "qualifying events acknowledged")
        manager.handleQualifyingEvents(events: events) { acknowledged.fulfill() }
        wait(for: [acknowledged], timeout: 60)
        delegateQueue.sync {}
    }

    /// The history tick an event kicks runs on after the event is acknowledged, and its fetch
    /// completes on the main queue.
    private func waitUntilReported(_ type: DoseType, timeout: TimeInterval = 10) {
        let deadline = Date().addingTimeInterval(timeout)
        while delegateQueue.sync(execute: { events(type).isEmpty }), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }

    func testAStopSeenAtAnAlarmIsDatedFromHistoryWithoutASync() {
        stubPump(serving: [resumed(at: start.addingTimeInterval(-60)), suspended(at: minutes(10))])
        advance(to: minutes(12))
        stubBasalStatus(1)

        handleQualifyingEvents([.alarm])
        waitUntilReported(.suspend)

        XCTAssertEqual(events(.suspend).map(\.date), [minutes(10)])
        XCTAssertEqual(manager.state.basalDose.startDate, minutes(10))
        XCTAssertNil(manager.state.deliveryTransitions.pending)
    }

    func testATempBasalAnAlarmStoppedEndsAtItsCompletionWithoutASync() throws {
        runningTempBasal(2.0)
        stubPump(serving: [
            resumed(at: start.addingTimeInterval(-60)),
            tempRateCompleted(7, at: minutes(8), timeLeft: 22 * 60),
            suspended(at: minutes(8))
        ])
        advance(to: minutes(11))
        stubBasalStatus(1)

        handleQualifyingEvents([.alarm])
        waitUntilReported(.suspend)

        let temp = try XCTUnwrap(events(.tempBasal).last)
        XCTAssertEqual(temp.dose?.isMutable, false)
        XCTAssertEqual(temp.dose?.endDate, minutes(8))
        XCTAssertEqual(events(.suspend).map(\.date), [minutes(8)])
    }

    func testWithTheFlagOffAStopSeenAtAMalfunctionIsReportedAtTheMalfunction() {
        manager.state.featureFlags[.historyBackfill] = false
        advance(to: minutes(12))
        stubBasalStatus(1)

        handleQualifyingEvents([.malfunction])

        XCTAssertEqual(events(.suspend).map(\.date), [minutes(12)])
    }

    // MARK: - A dose that finishes while the change waits (#556)

    private static let bolusId = 4100

    private func appBolus() throws -> Data {
        bluetooth.stub(BolusPermissionRequest.self, with: BolusPermissionResponse(status: 0, bolusId: Self.bolusId, nackReasonId: 0))
        bluetooth.stub(InitiateBolusRequest.self, with: InitiateBolusResponse(status: 0, bolusId: Self.bolusId, statusTypeId: 0))
        let done = expectation(description: "enactBolus")
        manager.enactBolus(units: 2.0, activationType: .manualNoRecommendation) { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        delegateQueue.sync {}
        return try XCTUnwrap(events(.bolus).last?.raw)
    }

    /// The pump's answers once it has stopped the 2 U bolus at `deliveredMilliunits`.
    private func stubBolusOver(deliveredMilliunits: UInt32?) {
        bluetooth.stub(CurrentBolusStatusRequest.self, with: CurrentBolusStatusResponse(
            statusId: 0, bolusId: 0, timestamp: 0, requestedVolume: 2000, bolusSourceId: 0, bolusTypeBitmask: 0
        ))
        bluetooth.stub(LastBolusStatusRequest.self) { _ in
            deliveredMilliunits.map {
                LastBolusStatusResponse(
                    status: 0, bolusId: Self.bolusId, timestamp: 0, deliveredVolume: $0,
                    bolusStatusId: 0, bolusSourceId: 0, bolusTypeBitmask: 0, extendedBolusDuration: 0
                )
            }
        }
    }

    private func feedLoop() -> LoopDoseStoreOracle {
        let loop = LoopDoseStoreOracle()
        delegateQueue.sync {}
        delegate.feed(loop)
        return loop
    }

    private func feedTrio() -> TrioDoseStoreOracle {
        let trio = TrioDoseStoreOracle()
        delegateQueue.sync {}
        delegate.feed(trio)
        return trio
    }

    private func assertCarriesTheHeldTemp(
        _ tempRaw: Data,
        since index: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let replacing = batches.dropFirst(index).filter(\.replacePendingEvents)
        XCTAssertFalse(replacing.isEmpty, "the dose finishing goes out in a replacing batch", file: file, line: line)
        for batch in replacing {
            let temp = batch.events.first { $0.raw == tempRaw }
            XCTAssertEqual(temp?.dose?.isMutable, true, "the host still holds the temp basal: \(batch.events.map(\.raw))", file: file, line: line)
        }
        let loop = feedLoop()
        XCTAssertEqual(loop.dose(raw: tempRaw)?.isMutable, true, file: file, line: line)
        XCTAssertTrue(loop.deletedDoses.isEmpty, "Loop never revives a deleted dose: \(loop.deletedDoses.map(LoopDoseStoreOracle.describe))", file: file, line: line)
    }

    func testABolusThatEndsWhileAStopWaitsForHistoryLeavesTheHostItsTempBasal() throws {
        appTempBasal(2.0)
        let tempRaw = try XCTUnwrap(events(.tempBasal).last?.raw)
        let bolusRaw = try appBolus()
        let stoppedAt = minutes(2)
        advance(to: minutes(3))
        observe(1)
        XCTAssertNotNil(manager.state.deliveryTransitions.pending)
        let before = batches.count

        stubBolusOver(deliveredMilliunits: 800)
        manager.fetchBolusStatus(fromSync: false)
        delegateQueue.sync {}

        XCTAssertTrue(batches.dropFirst(before).contains { $0.events.contains { $0.raw == bolusRaw && $0.dose?.isMutable == false } })
        assertCarriesTheHeldTemp(tempRaw, since: before)
        XCTAssertEqual(manager.state.basalDose.type, .suspend, "status still shows the stop")

        pass([tempRateCompleted(50, at: stoppedAt, timeLeft: 28 * 60), suspended(at: stoppedAt)])

        let loop = feedLoop()
        let temp = try XCTUnwrap(loop.assertPermanent(raw: tempRaw))
        XCTAssertEqual(temp.dose.endDate, stoppedAt, "ended at the pump's stop")
        let finished = events.last { $0.raw == tempRaw }?.dose
        XCTAssertEqual(finished?.isMutable, false)
        XCTAssertEqual(try XCTUnwrap(finished?.deliveredUnits), 2.0 * 2 / 60, accuracy: 0.001)
        XCTAssertEqual(loop.assertPermanent(raw: bolusRaw)?.dose.deliveredUnits, 0.8)
        XCTAssertTrue(loop.deletedDoses.isEmpty)
        XCTAssertEqual(feedTrio().tempBasals.count, 1)
        XCTAssertEqual(events(.suspend).map(\.date), [stoppedAt])
    }

    func testAnOcclusionMidBolusRaisedAsOneEventEndsTheTempBasalAtThePumpsStop() throws {
        appTempBasal(2.0)
        let tempRaw = try XCTUnwrap(events(.tempBasal).last?.raw)
        let bolusRaw = try appBolus()
        let stoppedAt = minutes(2)
        stubPump(serving: [
            resumed(at: start.addingTimeInterval(-60)),
            tempRateCompleted(50, at: stoppedAt, timeLeft: 28 * 60),
            suspended(at: stoppedAt)
        ])
        advance(to: minutes(3))
        stubBasalStatus(1)
        stubBolusOver(deliveredMilliunits: 800)
        let before = batches.count

        // Fetched in QualifyingEventFetch order: the basal read leaves the stop pending, then the bolus read finishes the bolus.
        handleQualifyingEvents([.alarm, .pumpSuspend, .bolusChange])
        waitUntilReported(.suspend)

        let loop = feedLoop()
        XCTAssertTrue(loop.deletedDoses.isEmpty, "\(loop.deletedDoses.map(LoopDoseStoreOracle.describe))")
        let temp = try XCTUnwrap(loop.assertPermanent(raw: tempRaw))
        XCTAssertEqual(temp.dose.endDate, stoppedAt)
        XCTAssertEqual(loop.assertPermanent(raw: bolusRaw)?.dose.deliveredUnits, 0.8)
        let trio = feedTrio()
        XCTAssertEqual(trio.tempBasals.count, 1, "\(trio.tempBasals)")
        XCTAssertEqual(trio.suspends.map(\.timestamp), [stoppedAt])
        let replacing = batches.dropFirst(before).filter(\.replacePendingEvents)
        XCTAssertTrue(replacing.allSatisfy { $0.events.contains { $0.raw == tempRaw } }, "\(replacing.map { $0.events.map(\.raw) })")
    }

    func testABolusCancelledWhileATempEndWaitsForHistoryLeavesTheHostItsTempBasal() throws {
        appTempBasal(2.0)
        let tempRaw = try XCTUnwrap(events(.tempBasal).last?.raw)
        _ = try appBolus()
        let endedAt = minutes(2)
        advance(to: minutes(3))
        observe(0)
        XCTAssertNotNil(manager.state.deliveryTransitions.pending)
        bluetooth.stub(CancelBolusRequest.self, with: CancelBolusResponse(statusId: 0, bolusId: Self.bolusId, reasonId: 0))
        stubBolusOver(deliveredMilliunits: 900)
        let before = batches.count

        let cancelled = expectation(description: "cancelBolus")
        manager.cancelBolus { result in
            if case let .failure(error) = result {
                XCTFail("cancelBolus failed: \(error)")
            }
            cancelled.fulfill()
        }
        wait(for: [cancelled], timeout: 10)
        delegateQueue.sync {}

        assertCarriesTheHeldTemp(tempRaw, since: before)
        XCTAssertNotNil(manager.state.deliveryTransitions.pending, "a bolus cancel changes no basal, so the change keeps its history dating")

        pass([tempRateCompleted(50, at: endedAt, timeLeft: 28 * 60)])

        XCTAssertEqual(try XCTUnwrap(feedLoop().assertPermanent(raw: tempRaw)).dose.endDate, endedAt)
    }

    func testABolusHeldForItsVolumeThatSettlesWhileAStopWaitsLeavesTheHostItsTempBasal() throws {
        appTempBasal(2.0)
        let tempRaw = try XCTUnwrap(events(.tempBasal).last?.raw)
        let bolusRaw = try appBolus()
        advance(to: minutes(1))
        stubBolusOver(deliveredMilliunits: nil)
        manager.fetchBolusStatus(fromSync: false)
        XCTAssertNotNil(manager.state.pendingBolusFinalization)
        advance(to: minutes(3))
        observe(1)
        let before = batches.count

        stubBolusOver(deliveredMilliunits: 2000)
        manager.finalizePendingBolus()
        delegateQueue.sync {}

        XCTAssertNil(manager.state.pendingBolusFinalization)
        XCTAssertEqual(feedLoop().dose(raw: bolusRaw)?.isMutable, false)
        assertCarriesTheHeldTemp(tempRaw, since: before)
    }

    func testATempThePumpRunsInPlaceOfTheHeldOneIsNotCutAtASegmentChangeWhenABolusEnds() throws {
        let segmentChange = minutes(10)
        manager.state.basalRateSchedule = BasalRateSchedule(dailyItems: [
            RepeatingScheduleValue(startTime: 0, value: Self.scheduledRate),
            RepeatingScheduleValue(startTime: segmentChange.timeIntervalSince(Calendar.current.startOfDay(for: segmentChange)), value: 2.0)
        ])!
        appTempBasal(1.5)
        let tempRaw = try XCTUnwrap(events(.tempBasal).last?.raw)
        _ = try appBolus()
        // Read before the change, so the pump's 1 U/hr profile still matches the schedule.
        advance(to: minutes(8))
        observeTemp(percent: 120, from: minutes(5))
        XCTAssertNotNil(manager.state.deliveryTransitions.pending?.replacement)
        let held = manager.state.basalDose
        advance(to: minutes(12))
        let before = batches.count

        stubBolusOver(deliveredMilliunits: 2000)
        manager.fetchBolusStatus(fromSync: false)
        delegateQueue.sync {}

        let temps = batches.dropFirst(before).flatMap(\.events).filter { $0.dose?.type == .tempBasal }
        XCTAssertEqual(temps.map(\.raw), [tempRaw], "the held temp as the host holds it, uncut")
        XCTAssertEqual(temps.first?.dose?.isMutable, true)
        XCTAssertTrue(manager.state.basalDose === held)

        pass([tempRateCompleted(50, at: minutes(5), timeLeft: 25 * 60), tempRateActivated(51, at: minutes(5), percent: 120)])

        let loop = feedLoop()
        XCTAssertEqual(try XCTUnwrap(loop.assertPermanent(raw: tempRaw)).dose.endDate, minutes(5), "the held temp ended where the pump's replaced it")
        XCTAssertFalse(
            loop.doses.contains { $0.dose.type == .tempBasal && $0.dose.startDate == start && $0.dose.endDate == segmentChange },
            "\(loop.doses.map(LoopDoseStoreOracle.describe))"
        )
    }

    func testEnablingControlIQWhileAReplacingTempWaitsForHistoryReportsItFirst() throws {
        appTempBasal(1.5)
        let tempRaw = try XCTUnwrap(events(.tempBasal).last?.raw)
        advance(to: minutes(8))
        observeTemp(percent: 120, from: minutes(5))
        XCTAssertNotNil(manager.state.deliveryTransitions.pending?.replacement)
        bluetooth.stub(ChangeControlIQSettingsRequest.self, with: ChangeControlIQSettingsResponse(status: 1))

        let done = expectation(description: "configureControlIQMode")
        manager.configureControlIQMode(ChangeControlIQSettingsRequest(enabled: true, weightLbs: 150, totalDailyInsulinUnits: 30)) { _ in
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        delegateQueue.sync {}

        XCTAssertNil(manager.state.deliveryTransitions.pending)
        XCTAssertTrue(bluetooth.didSend(StopTempRateRequest.self), "the temp the pump runs is stopped before Control-IQ takes over")
        let loop = feedLoop()
        XCTAssertEqual(try XCTUnwrap(loop.assertPermanent(raw: tempRaw)).dose.endDate, minutes(5), "the held temp ended where the pump's replaced it")
        XCTAssertEqual(manager.state.basalDose.type, .basal)
    }

    // MARK: - A temp basal the pump resumes after a stop

    /// The pump's temp 7 at 200% of its 1 U/hr from `start` for 30 minutes, stopped at `stoppedAt`
    /// by an occlusion, which writes no `TempRateCompleted` for it.
    private func occlusionStopsTheTempBasal(at stoppedAt: Date, detectedAt: Date) {
        runningTempBasal(2.0, percent: 200)
        advance(to: detectedAt)
        observe(1)
        pass([suspended(at: stoppedAt)])
    }

    private func observeTempRate(_ unitsPerHour: Double) {
        bluetooth.stub(CurrentBasalStatusRequest.self, with: CurrentBasalStatusResponse(
            profileBasalRate: 1000,
            currentBasalRate: UInt32(unitsPerHour * 1000),
            basalModifiedBitmask: 2
        ))
        manager.fetchBasalStatus()
        delegateQueue.sync {}
    }

    private func resumedTemps() -> [NewPumpEvent] {
        events(.tempBasal).filter { $0.dose?.startDate != start }
    }

    func testATempBasalAnOcclusionInterruptedIsReportedAgainFromAnAppResume() throws {
        occlusionStopsTheTempBasal(at: minutes(5), detectedAt: minutes(6))
        let interrupted = try XCTUnwrap(events(.tempBasal).first)
        XCTAssertEqual(interrupted.dose?.endDate, minutes(5))

        advance(to: minutes(8))
        stubBasalStatus(1)
        appResume()
        advance(to: minutes(8).addingTimeInterval(1))
        observeTempRate(2.0)

        let resumed = try XCTUnwrap(resumedTemps().last)
        XCTAssertEqual(resumedTemps().count, 1)
        XCTAssertNotEqual(resumed.raw, interrupted.raw, "neither host would store a second row under the finished one's raw")
        XCTAssertEqual(resumed.dose?.isMutable, true)
        XCTAssertEqual(resumed.dose?.startDate, minutes(8).addingTimeInterval(1), "a second after the resume, which Trio would otherwise order arbitrarily")
        XCTAssertEqual(resumed.dose?.endDate, minutes(30), "the stop does not move the temp's programmed end")
        XCTAssertEqual(resumed.dose?.unitsPerHour, 2.0)
        XCTAssertEqual(manager.state.basalDose.type, .tempBasal)
        XCTAssertEqual(manager.state.basalDose.tempRateId, 7)
        XCTAssertNil(manager.state.deliveryTransitions.interruptedTemp)

        let segments = try feedTrio().basalSegments(clock: minutes(10))
        XCTAssertEqual(segments.last { $0.start <= minutes(9) }?.rate, 2.0, "Trio counts the rate the pump runs")
        XCTAssertTrue(feedLoop().deletedDoses.isEmpty)
    }

    func testATempBasalAStopInterruptedIsReportedAgainOnlyOnce() {
        occlusionStopsTheTempBasal(at: minutes(5), detectedAt: minutes(6))
        advance(to: minutes(8))
        stubBasalStatus(1)
        appResume()
        observeTempRate(2.0)
        advance(to: minutes(9))
        observeTempRate(2.0)

        XCTAssertEqual(resumedTemps().count, 1)
    }

    func testATempBasalAPumpSideResumeRestartsIsReportedFromTheResume() throws {
        occlusionStopsTheTempBasal(at: minutes(5), detectedAt: minutes(6))
        advance(to: minutes(12))
        observeTempRate(2.0)
        XCTAssertTrue(resumedTemps().isEmpty, "the resume is dated from history first")

        pass([resumed(at: minutes(10))])

        XCTAssertEqual(events(.resume).map(\.date), [minutes(10)])
        let resumed = try XCTUnwrap(resumedTemps().last)
        XCTAssertEqual(resumed.dose?.startDate, minutes(10).addingTimeInterval(1))
        XCTAssertEqual(resumed.dose?.endDate, minutes(30))
        XCTAssertEqual(resumed.dose?.isMutable, true)
        XCTAssertTrue(try XCTUnwrap(batches.last).replacePendingEvents, "the host holds the resumed temp as mutable")
        XCTAssertEqual(manager.state.basalDose.type, .tempBasal)
    }

    func testWithTheFlagOffATempBasalAStopInterruptedIsReportedAgainFromTheResume() throws {
        manager.state.featureFlags[.historyBackfill] = false
        runningTempBasal(2.0, percent: 200)
        advance(to: minutes(6))
        observe(1)
        advance(to: minutes(8))
        appResume()
        observeTempRate(2.0)

        let resumed = try XCTUnwrap(resumedTemps().last { $0.dose?.isMutable == true })
        XCTAssertEqual(resumed.dose?.startDate, minutes(8).addingTimeInterval(1))
        XCTAssertEqual(resumed.dose?.endDate, minutes(30))
    }

    func testATempBasalTheStopCompletedIsNotReportedAgain() {
        runningTempBasal(2.0, percent: 200)
        advance(to: minutes(6))
        observe(1)
        pass([tempRateCompleted(7, at: minutes(5), timeLeft: 25 * 60), suspended(at: minutes(5))])
        advance(to: minutes(8))
        stubBasalStatus(1)
        appResume()
        observeTempRate(2.0)

        XCTAssertTrue(resumedTemps().isEmpty, "the pump ended it, so the temp it runs is not the app's")
    }

    func testAStopPastTheTempsProgrammedEndResumesNothing() {
        occlusionStopsTheTempBasal(at: minutes(5), detectedAt: minutes(6))
        advance(to: minutes(31))
        stubBasalStatus(1)
        appResume()
        observeTempRate(2.0)

        XCTAssertTrue(resumedTemps().isEmpty)
    }

    func testATempAtAnotherRateAfterTheResumeIsNotTakenForTheInterruptedOne() {
        occlusionStopsTheTempBasal(at: minutes(5), detectedAt: minutes(6))
        advance(to: minutes(8))
        stubBasalStatus(1)
        appResume()
        observeTempRate(3.0)

        XCTAssertTrue(resumedTemps().isEmpty)
        XCTAssertNil(manager.state.deliveryTransitions.interruptedTemp)
    }

    func testScheduledBasalAfterTheResumeForgetsTheInterruptedTemp() {
        occlusionStopsTheTempBasal(at: minutes(5), detectedAt: minutes(6))
        advance(to: minutes(8))
        stubBasalStatus(1)
        appResume()
        observe(0)
        observeTempRate(2.0)

        XCTAssertTrue(resumedTemps().isEmpty)
    }

    func testAnAppCancelForgetsTheInterruptedTemp() {
        occlusionStopsTheTempBasal(at: minutes(5), detectedAt: minutes(6))
        advance(to: minutes(8))
        stubBasalStatus(1)
        appResume()
        XCTAssertNotNil(manager.state.deliveryTransitions.interruptedTemp)
        manager.startScheduledBasalDose()

        XCTAssertNil(manager.state.deliveryTransitions.interruptedTemp)
    }

    func testTheInterruptedTempSurvivesARelaunch() throws {
        occlusionStopsTheTempBasal(at: minutes(5), detectedAt: minutes(6))
        manager = makeManager(state: try XCTUnwrap(TandemPumpManagerState(rawValue: manager.state.rawValue)))
        advance(to: minutes(8))
        stubBasalStatus(1)
        appResume()
        observeTempRate(2.0)

        XCTAssertEqual(resumedTemps().count, 1)
    }

    // MARK: - What history never reports

    func testAResumeWithNoSuspendBeforeItIsNotReported() {
        advance(to: minutes(30))
        pass([resumed(at: minutes(5))])

        XCTAssertTrue(batches.isEmpty, "Trio would take the pump as suspended until the resume")
    }

    func testAResumeWhoseSuspendArrivesLaterFromAGapIsReportedWithIt() {
        let suspend = suspended(at: minutes(5))
        let resume = resumed(at: minutes(15))
        advance(to: minutes(30))
        pass([resume])
        XCTAssertTrue(batches.isEmpty)

        pass([suspend])

        XCTAssertEqual(events.map(\.dose?.type), [.suspend, .resume], "never a suspend without the resume that closes it")
        XCTAssertEqual(events.map(\.date), [minutes(5), minutes(15)])
    }

    func testASuspendAndResumeInTheSameSecondAreNotReported() {
        advance(to: minutes(30))
        pass([suspended(at: minutes(5)), resumed(at: minutes(5))])
        pass([])

        XCTAssertTrue(batches.isEmpty)
    }

    func testASuspendWhoseResumeIsNotReadYetWaitsWhileThePumpDelivers() {
        advance(to: minutes(30))
        pass([suspended(at: minutes(5))])
        XCTAssertTrue(batches.isEmpty, "Trio would take a trailing suspend as lasting until now")

        pass([resumed(at: minutes(15))])

        XCTAssertEqual(events.map(\.dose?.type), [.suspend, .resume])
    }

    func testASecondSuspendInARowIsNotReported() {
        appSuspend()
        let appRecord = suspended(at: start.addingTimeInterval(1))
        advance(to: minutes(30))

        pass([appRecord, suspended(at: minutes(10))])

        XCTAssertEqual(events(.suspend).count, 1, "Loop keeps only the later of two suspends")
    }

    func testAnAppSuspendIsNotReportedAgainFromHistory() {
        appSuspend()
        let reported = events.count

        pass([suspended(at: start.addingTimeInterval(2))])

        XCTAssertEqual(events.count, reported)
        XCTAssertEqual(manager.state.deliveryTransitions.entries.first?.sequenceNum, Self.firstSequenceNum)
    }

    func testAnAppResumeIsNotReportedAgainFromHistory() {
        appSuspend()
        let suspendRecord = suspended(at: start.addingTimeInterval(1))
        advance(to: minutes(10))
        appResume()
        let reported = events.count

        pass([suspendRecord, resumed(at: minutes(10).addingTimeInterval(1))])

        XCTAssertEqual(events.count, reported)
    }

    func testAnAppResumeWhoseAnswerWasLostIsNotReportedAgainFromHistory() {
        appSuspend()
        let suspendRecord = suspended(at: start.addingTimeInterval(1))
        advance(to: minutes(10))
        stubBasalStatus(1)
        bluetooth.stub(ResumePumpingRequest.self) { [unowned self] _ in
            self.stubBasalStatus(0)
            self.clock.advance(by: 30)
            return nil
        }
        let done = expectation(description: "resumeDelivery")
        manager.resumeDelivery { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        delegateQueue.sync {}
        XCTAssertEqual(events(.resume).map(\.date), [minutes(10)])
        let reported = events.count

        pass([suspendRecord, resumed(at: minutes(10).addingTimeInterval(2))])

        XCTAssertEqual(events.count, reported)
    }

    func testAPassRunTwiceReportsNothingTheSecondTime() {
        advance(to: minutes(30))
        pass([suspended(at: minutes(5)), resumed(at: minutes(15))])
        let reported = events.count

        pass([])

        XCTAssertEqual(events.count, reported)
    }

    func testRecordsOlderThanTheRetentionAreNotReported() {
        advance(to: minutes(30).addingTimeInterval(DeliveryTransitionLedger.retention))

        pass([suspended(at: minutes(5)), resumed(at: minutes(15))])

        XCTAssertTrue(batches.isEmpty)
    }

    func testRecordsDatedAheadOfThePhoneAreNotReported() {
        pass([suspended(at: minutes(5)), resumed(at: minutes(15))])

        XCTAssertTrue(batches.isEmpty)
    }

    // MARK: - The host's view

    func testAResumeIsReportedWhenTheHostsSuspendPredatesTheLedger() {
        manager.state.basalDose = UnfinalizedDose(suspendStartTime: start)
        advance(to: minutes(30))
        observe(0)

        pass([resumed(at: minutes(12))])

        XCTAssertEqual(events(.resume).map(\.date), [minutes(12)], "the host holds the suspend; without a resume Trio keeps it open")
        XCTAssertEqual(manager.state.basalDose.type, .resume)
    }

    func testAResumeIsReportedWhenTheHostsSuspendIsOlderThanTheLedgerKeepsAndHistoryHasNoRecord() {
        manager.state.basalDose = UnfinalizedDose(suspendStartTime: start.addingTimeInterval(-.hours(30)))
        advance(to: minutes(5))
        observe(1)
        advance(to: minutes(30))
        observe(0)

        pass([suspended(at: minutes(1))])

        XCTAssertEqual(events(.resume).map(\.date), [minutes(5)])
    }

    // MARK: - Tracking

    func testTrackingStartsAfterThePumpsLastRecordOnFirstSight() {
        manager.state.deliveryTransitions = DeliveryTransitionLedger()
        advance(to: minutes(30))

        pass([suspended(at: minutes(5)), resumed(at: minutes(15))])
        XCTAssertTrue(batches.isEmpty, "records from before the driver watched this pump")
        XCTAssertEqual(manager.state.deliveryTransitions.trackedAfter, Self.firstSequenceNum + 1)

        pass([suspended(at: minutes(20)), resumed(at: minutes(25))])
        XCTAssertEqual(events.map(\.date), [minutes(20), minutes(25)])
    }

    func testTrackingStartsFromTheStatusOfATickWhoseReadFailed() {
        manager.state.deliveryTransitions = DeliveryTransitionLedger()
        _ = manager.reportHistoryDeliveryTransitions(
            after: HistoryBackfillCoordinator.TickOutcome(
                bookkeeping: HistoryBackfillState(pumpSerial: Self.pumpSerial),
                rangesRead: [],
                sessionCovered: nil,
                isDeepBackfillComplete: false,
                emitFloor: .distantPast,
                startedAt: clock.now,
                pumpSequenceRange: 1 ... Self.firstSequenceNum - 1
            ),
            pumpSerial: serial
        )
        XCTAssertEqual(manager.state.deliveryTransitions.trackedAfter, Self.firstSequenceNum - 1)
        advance(to: minutes(30))
        observe(1)

        pass([suspended(at: minutes(10))])

        XCTAssertEqual(events(.suspend).map(\.date), [minutes(10)], "written after the status that started tracking")
    }

    func testAnotherPumpOrAnErasedLogStartsTrackingAgain() {
        var ledger = DeliveryTransitionLedger(pumpSerial: 1, trackedAfter: 100)
        ledger.record(DeliveryTransitionLedger.Entry(kind: .suspend, date: start, earliest: start, latest: start, sequenceNum: 150, isReported: true))
        ledger.record(DeliveryTransitionLedger.Entry(kind: .resume, date: start, earliest: start, latest: start, sequenceNum: 151, isReported: false))

        XCTAssertTrue(ledger.isTracking(pumpSerial: 1, lastSequenceNum: 200))
        XCTAssertFalse(ledger.isTracking(pumpSerial: 2, lastSequenceNum: 200))
        XCTAssertFalse(ledger.isTracking(pumpSerial: 1, lastSequenceNum: 99), "an erased log restarts its numbering")

        ledger.track(pumpSerial: 2, after: 20)

        XCTAssertEqual(ledger.trackedAfter, 20)
        XCTAssertEqual(ledger.entries.map(\.sequenceNum), [nil], "the host still holds the suspend; no record of this pump accounts for it")
        XCTAssertFalse(ledger.isHandled(sequenceNum: 150))
    }

    func testLedgerRoundTripsThroughRawValue() {
        var ledger = DeliveryTransitionLedger(
            pumpSerial: Self.pumpSerial,
            trackedAfter: 41,
            pending: DeliveryTransitionLedger.PendingTransition(
                prior: UnfinalizedDose(tempRate: 1.5, duration: 1800, automatic: true, insulinType: .novolog, startDate: start, tempRateId: 3),
                observed: .tempBasal,
                detectedAt: minutes(20),
                lastConfirmed: minutes(2),
                replacement: DeliveryTransitionLedger.PendingTransition.ReplacingTemp(start: minutes(5), percent: 120, rate: 1.2)
            ),
            lastConfirmedObservation: minutes(2),
            interruptedTemp: UnfinalizedDose(
                tempRate: 2.0,
                duration: .minutes(30),
                automatic: true,
                insulinType: .novolog,
                startDate: minutes(0),
                tempRateId: 7,
                tempPercent: 200
            )
        )
        ledger.record(DeliveryTransitionLedger.Entry(
            kind: .suspend,
            date: minutes(1),
            earliest: minutes(0),
            latest: minutes(2),
            sequenceNum: 42,
            isReported: true
        ))
        ledger.record(DeliveryTransitionLedger.Entry(
            kind: .resume,
            date: minutes(3),
            earliest: minutes(3),
            latest: minutes(3),
            sequenceNum: nil,
            isReported: false
        ))

        XCTAssertEqual(DeliveryTransitionLedger(rawValue: ledger.rawValue), ledger)
    }
}
