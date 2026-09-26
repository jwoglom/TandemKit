import LoopKit
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class DeliveryTransitionReportingTests: XCTestCase {
    private static let pumpSerial: UInt32 = 123_456
    private let serial = HistoryLogSyncIdentifier.PumpSerial(DeliveryTransitionReportingTests.pumpSerial)!
    private static let scheduledRate = 1.0

    private var bluetooth: StubPumpBluetooth!
    private var clock: ManualClock!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!

    /// Whole seconds: pump timestamps are.
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var nextSequenceNum: UInt32 = 1000

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
        state.deliveryTransitions = DeliveryTransitionLedger(trackingSince: .distantPast)
        // The tick's floor includes the bolus ledger's, which otherwise starts at the wall clock.
        state.bolusReportLedger = BolusReportLedger(trackingSince: .distantPast)
        return state
    }

    private func makeManager(state: TandemPumpManagerState) -> TandemPumpManager {
        let manager = TandemPumpManager(state: state, bluetooth: bluetooth, clock: clock)
        delegate = MockPumpManagerDelegate()
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
    private func observe(_ bitmask: Int) {
        bluetooth.stub(CurrentBasalStatusRequest.self, with: CurrentBasalStatusResponse(
            profileBasalRate: 1000,
            currentBasalRate: bitmask == 1 ? 0 : 1000,
            basalModifiedBitmask: bitmask
        ))
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

    private func tempRateCompleted(_ tempRateId: Int, at date: Date) -> HistoryLog {
        TempRateCompletedHistoryLog(pumpTimeSec: pumpTimeSec(date), sequenceNum: takeSequenceNum(), tempRateId: tempRateId, timeLeft: 0)
    }

    /// Stores `logs` and runs the history pass as a tick that read the pump's log to its end now.
    private func pass(_ logs: [HistoryLog], completeThrough: Date? = nil) {
        manager.storeHistoryLogs(logs, now: clock.now)
        let sequences = (try? manager.historyLogStore.logs(pumpSerial: Self.pumpSerial, in: 0 ... UInt32.max))?.map(\.sequenceNum) ?? []
        guard let first = sequences.min(), let last = sequences.max() else { return }
        manager.reportHistoryDeliveryTransitions(
            in: first ... last,
            pumpSerial: serial,
            floor: .distantPast,
            completeThrough: completeThrough ?? clock.now,
            reachesBack: true,
            now: clock.now
        )
        delegateQueue.sync {}
    }

    private var batches: [MockPumpManagerDelegate.PumpEventBatch] { delegate.pumpEventBatches }

    private var events: [NewPumpEvent] { batches.flatMap(\.events) }

    private func events(_ type: DoseType) -> [NewPumpEvent] {
        events.filter { $0.dose?.type == type }
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

    // MARK: - The four outage cases

    func testASuspendDuringAnOutageIsReportedAtThePumpsTimeNotAtReconnect() throws {
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

    func testASuspendAndResumeBothInsideAnOutageAreReportedAsAPair() throws {
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
        let resume = try XCTUnwrap(events(.resume).first)
        XCTAssertEqual(events(.resume).count, 1)
        XCTAssertEqual(resume.date, minutes(12))
        XCTAssertEqual(manager.state.basalDose.type, .resume)
        XCTAssertEqual(manager.state.basalDose.startDate, minutes(12))
    }

    func testATempBasalStoppedByAnOutageSuspendEndsAtTheSuspend() throws {
        manager.state.basalDose = UnfinalizedDose(
            tempRate: 2.0,
            duration: .minutes(30),
            automatic: true,
            insulinType: .novolog,
            startDate: start,
            tempRateId: 7
        )
        advance(to: minutes(20))
        observe(1)
        XCTAssertTrue(batches.isEmpty)

        pass([tempRateCompleted(7, at: minutes(8)), suspended(at: minutes(8))])

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

    func testATempBasalThatRanOutDuringAnOutageEndsAtItsScheduledEnd() throws {
        manager.state.basalDose = UnfinalizedDose(
            tempRate: 2.0,
            duration: .minutes(30),
            automatic: true,
            insulinType: .novolog,
            startDate: start,
            tempRateId: 8
        )
        advance(to: minutes(50))
        observe(0)

        pass([tempRateCompleted(8, at: minutes(30))])

        let temp = try XCTUnwrap(events(.tempBasal).first)
        XCTAssertEqual(temp.dose?.endDate, minutes(30))
        XCTAssertEqual(events(.basal).first?.date, minutes(30), "scheduled basal resumes at the temp basal's end")
        XCTAssertEqual(manager.state.basalDose.type, .basal)
    }

    // MARK: - Waiting for history, and giving up on it

    func testNothingIsReportedUntilHistoryHasBeenReadPastTheChange() {
        advance(to: minutes(30))
        observe(1)

        pass([suspended(at: minutes(10))], completeThrough: minutes(29))

        XCTAssertTrue(batches.isEmpty)
        XCTAssertNotNil(manager.state.deliveryTransitions.pending)
    }

    func testAChangeHistoryNeverDatesIsReportedAtDetectionAfterTheDeadline() throws {
        advance(to: minutes(30))
        observe(1)

        advance(to: minutes(30).addingTimeInterval(TandemPumpManager.historyTransitionDeadline + 1))
        observe(1)

        let suspend = try XCTUnwrap(events(.suspend).first)
        XCTAssertEqual(suspend.date, minutes(30), "the latest the stop can have been, which counts more insulin")
        XCTAssertNil(manager.state.deliveryTransitions.pending)
    }

    func testAResumeHistoryNeverDatesIsReportedAtTheLastSuspendedReading() throws {
        appSuspend()
        advance(to: minutes(5))
        observe(1)
        advance(to: minutes(30))
        observe(0)

        advance(to: minutes(30).addingTimeInterval(TandemPumpManager.historyTransitionDeadline + 1))
        observe(0)

        let resume = try XCTUnwrap(events(.resume).first)
        XCTAssertEqual(resume.date, minutes(5), "the earliest the pump can have resumed, which counts more insulin")
    }

    func testTurningTheFlagOffReportsAPendingChangeAtDetection() throws {
        advance(to: minutes(30))
        observe(1)
        manager.state.featureFlags[.historyBackfill] = false

        advance(to: minutes(31))
        observe(1)

        XCTAssertEqual(events(.suspend).map(\.date), [minutes(30)])
    }

    func testAChangeWhoseRecordIsBelowTheFloorIsReportedAtDetection() {
        manager.state.deliveryTransitions = DeliveryTransitionLedger(trackingSince: minutes(20))
        advance(to: minutes(30))
        observe(1)

        pass([suspended(at: minutes(10))])

        XCTAssertEqual(events(.suspend).map(\.date), [minutes(30)], "the host was never sent the record, so it cannot be the state")
    }

    // MARK: - What is never reported

    func testAResumeWithNoSuspendBeforeItIsNotReported() {
        pass([resumed(at: minutes(5))])

        XCTAssertTrue(batches.isEmpty, "Trio would take the pump as suspended until the resume")
    }

    func testASuspendAndResumeInTheSameSecondAreNotReported() {
        pass([suspended(at: minutes(5)), resumed(at: minutes(5))])

        XCTAssertTrue(batches.isEmpty)
    }

    func testASuspendWhoseResumeIsNotReadYetWaitsWhileThePumpDelivers() {
        let suspend = suspended(at: minutes(5))
        pass([suspend])
        XCTAssertTrue(batches.isEmpty, "Trio would take a trailing suspend as lasting until now")

        pass([resumed(at: minutes(15))])

        XCTAssertEqual(events.map(\.dose?.type), [.suspend, .resume])
    }

    func testAnAppSuspendIsNotReportedAgainFromHistory() {
        appSuspend()
        let reported = events.count

        pass([suspended(at: start.addingTimeInterval(2))])

        XCTAssertEqual(events.count, reported)
        XCTAssertEqual(manager.state.deliveryTransitions.entries.first?.sequenceNum, 1000)
    }

    func testAPassRunTwiceReportsNothingTheSecondTime() {
        pass([suspended(at: minutes(5)), resumed(at: minutes(15))])
        let reported = events.count

        pass([])
        manager.reportHistoryDeliveryTransitions(
            in: 1000 ... 1001,
            pumpSerial: serial,
            floor: .distantPast,
            completeThrough: clock.now,
            reachesBack: true,
            now: clock.now
        )
        delegateQueue.sync {}

        XCTAssertEqual(events.count, reported)
    }

    func testRecordsBeforeTheLedgerStartedTrackingAreNotReported() {
        manager.state.deliveryTransitions = DeliveryTransitionLedger(trackingSince: minutes(20))

        pass([suspended(at: minutes(5)), resumed(at: minutes(15))])

        XCTAssertTrue(batches.isEmpty)
    }

    // MARK: - Through the backfill tick

    /// Serves `logs` the way the pump does: status from their range, entries streamed back on
    /// `historyLogStream` after the request is acknowledged.
    private func stubPump(serving logs: [HistoryLog]) {
        let bySequence = Dictionary(uniqueKeysWithValues: logs.map { ($0.sequenceNum, $0) })
        let sequences = logs.map(\.sequenceNum)
        bluetooth.stub(HistoryLogStatusRequest.self, with: HistoryLogStatusResponse(
            numEntries: UInt32(logs.count),
            firstSequenceNum: sequences.min()!,
            lastSequenceNum: sequences.max()!
        ))
        bluetooth.stub(HistoryLogRequest.self, with: HistoryLogResponse(status: 0, streamId: 7))
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

    func testTheTickTheLivePathKicksDatesTheSuspendItSaw() {
        stubPump(serving: [resumed(at: start.addingTimeInterval(-60)), suspended(at: minutes(10))])
        advance(to: minutes(30))
        observe(1)

        let deadline = Date().addingTimeInterval(60)
        while events(.suspend).isEmpty, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            delegateQueue.sync {}
        }

        XCTAssertEqual(events(.suspend).map(\.date), [minutes(10)])
        XCTAssertTrue(events(.resume).isEmpty, "the resume before the outage had no suspend to close")
    }

    // MARK: - Clocks and persistence

    func testHistoryTimesAreMovedOntoThePhonesClock() throws {
        manager.state.currentPumpTime = minutes(0).addingTimeInterval(120)
        manager.state.lastPumpTimeCheckDate = minutes(0)
        advance(to: minutes(30))
        observe(1)

        pass([suspended(at: minutes(10), pumpAhead: 120)])

        XCTAssertEqual(events(.suspend).first?.date, minutes(10))
    }

    func testWithTheFlagOffTheLivePathStillReportsAtDetection() throws {
        manager.state.featureFlags[.historyBackfill] = false
        advance(to: minutes(30))
        observe(1)

        XCTAssertEqual(events(.suspend).map(\.date), [minutes(30)])
        let entry = try XCTUnwrap(manager.state.deliveryTransitions.entries.first)
        XCTAssertEqual(entry.earliest, start.addingTimeInterval(-TandemPumpManager.transitionMatchTolerance), "its pump record can be anywhere since the last reading")
    }

    func testAPendingChangeSurvivesARelaunch() {
        advance(to: minutes(30))
        observe(1)

        manager = makeManager(state: TandemPumpManagerState(rawValue: manager.state.rawValue))
        pass([suspended(at: minutes(10))])

        XCTAssertEqual(events(.suspend).map(\.date), [minutes(10)])
    }

    func testLedgerRoundTripsThroughRawValue() {
        var ledger = DeliveryTransitionLedger(
            trackingSince: Date(timeIntervalSinceReferenceDate: 1000),
            pending: DeliveryTransitionLedger.PendingTransition(
                prior: UnfinalizedDose(tempRate: 1.5, duration: 1800, automatic: true, insulinType: .novolog, startDate: start, tempRateId: 3),
                observed: .suspend,
                detectedAt: minutes(20),
                lastConfirmed: minutes(2)
            ),
            lastConfirmedObservation: minutes(2)
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
