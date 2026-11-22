import LoopKit
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class HistoryDoseReportingTests: XCTestCase {
    private static let pumpSerial: UInt32 = 123_456
    private let serial = HistoryLogSyncIdentifier.PumpSerial(HistoryDoseReportingTests.pumpSerial)!

    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!

    private let now = Date()
    private lazy var phoneNowPumpTimeSec = UInt32(Dates.fromInstantToJan12008EpochSeconds(now))
    private var pumpClockAhead: UInt32 = 0
    private var nowPumpTimeSec: UInt32 { phoneNowPumpTimeSec + pumpClockAhead }

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        bluetooth.stubPumpClock()
        manager = makeManager(state: Self.reportingEnabledState())
    }

    override func tearDown() {
        manager = nil
        delegate = nil
        bluetooth = nil
        super.tearDown()
    }

    private static func reportingEnabledState() -> TandemPumpManagerState {
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.historyBackfill] = true
        state.featureFlags[.historyDoseReporting] = true
        state.pumpState.pumpSerial = pumpSerial
        state.bolusReportLedger = BolusReportLedger(trackingSince: .distantPast)
        return state
    }

    private func makeManager(state: TandemPumpManagerState) -> TandemPumpManager {
        let manager = TandemPumpManager(state: state, bluetooth: bluetooth)
        delegate = MockPumpManagerDelegate()
        manager.pumpManagerDelegate = delegate
        manager.waitForDelegateCalls()
        return manager
    }

    // MARK: - Fixtures

    /// The records the pump writes for a quick bolus, in order, `secondsAgo` before now.
    private func quickBolusStart(bolusId: Int, units: Float, firstSequenceNum: UInt32, secondsAgo: UInt32) -> [HistoryLog] {
        let requested = nowPumpTimeSec - secondsAgo
        let activated = requested + 14
        return [
            BolusRequestedMsg2HistoryLog(
                pumpTimeSec: requested,
                sequenceNum: firstSequenceNum,
                bolusId: bolusId,
                options: BolusRequestedMsg2HistoryLog.BolusOption.quick.rawValue,
                standardPercent: 100,
                duration: 0,
                spare1: 0,
                isf: 0,
                targetBG: 0,
                userOverride: false,
                declinedCorrection: false,
                selectedIOB: 0,
                spare2: 0
            ),
            BolusActivatedHistoryLog(
                pumpTimeSec: activated,
                sequenceNum: firstSequenceNum + 1,
                bolusId: bolusId,
                selectedIob: 0,
                iob: 0,
                bolusSize: units
            ),
            BolusDeliveryHistoryLog(
                pumpTimeSec: activated,
                sequenceNum: firstSequenceNum + 2,
                bolusID: bolusId,
                bolusDeliveryStatus: 1,
                bolusTypeBitmask: 1,
                bolusSource: BolusDeliveryHistoryLog.BolusSource.quickBolus.rawValue,
                remoteId: 0,
                requestedNow: Int(units * 1000),
                requestedLater: 0,
                correction: 0,
                extendedDurationRequested: 0,
                deliveredTotal: 0
            )
        ]
    }

    private func bolusCompletion(
        bolusId: Int,
        delivered: Float,
        requested: Float,
        sequenceNum: UInt32,
        secondsAgo: UInt32
    ) -> BolusCompletedHistoryLog {
        BolusCompletedHistoryLog(
            pumpTimeSec: nowPumpTimeSec - secondsAgo,
            sequenceNum: sequenceNum,
            completionStatusId: 3,
            bolusId: bolusId,
            iob: delivered,
            insulinDelivered: delivered,
            insulinRequested: requested
        )
    }

    private func pumpDate(_ log: HistoryLog) -> Date {
        Dates.fromJan12008EpochSecondsToDate(TimeInterval(log.pumpTimeSec))
    }

    private func report(_ logs: [HistoryLog], floor: Date? = nil) {
        manager.storeHistoryLogs(logs, now: now)
        let sequences = logs.map(\.sequenceNum)
        manager.reportHistoryBoluses(
            in: sequences.min()! ... sequences.max()!,
            pumpSerial: serial,
            floor: floor ?? now.addingTimeInterval(-BolusReportLedger.reportingHorizon),
            now: now
        )
        manager.waitForDelegateCalls()
    }

    private var reportedBoluses: [NewPumpEvent] {
        delegate.pumpEventBatches.flatMap(\.events).filter { $0.dose?.type == .bolus }
    }

    private func commandedEntry(bolusId: Int, isFinalized: Bool, decisionId: UUID? = nil) -> BolusReportLedger.Entry {
        BolusReportLedger.Entry(
            bolusId: bolusId,
            pumpSerial: Self.pumpSerial,
            origin: .commanded,
            raw: Data("bolus 1.0 live".utf8),
            eventDate: now.addingTimeInterval(-600),
            automatic: false,
            isFinalized: isFinalized,
            decisionId: decisionId
        )
    }

    // MARK: - Pump-UI boluses

    func testQuickBolusFromThePumpIsReportedOnceFinalized() throws {
        let start = quickBolusStart(bolusId: 42, units: 2.0, firstSequenceNum: 100, secondsAgo: 300)
        // The pump stores delivered volume as a Float; 2.0 U comes back as 1.9999998.
        let completion = bolusCompletion(bolusId: 42, delivered: 1.9999998, requested: 2.0, sequenceNum: 103, secondsAgo: 240)

        report(start + [completion])

        XCTAssertEqual(delegate.pumpEventBatches.count, 1)
        XCTAssertEqual(delegate.pumpEventBatches.first?.replacePendingEvents, false)
        let event = try XCTUnwrap(reportedBoluses.first)
        XCTAssertEqual(reportedBoluses.count, 1)
        XCTAssertEqual(event.raw, HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: 42))
        XCTAssertEqual(event.date, pumpDate(start[1]))

        let dose = try XCTUnwrap(event.dose)
        XCTAssertFalse(dose.isMutable)
        XCTAssertEqual(dose.deliveredUnits, 2.0)
        XCTAssertEqual(dose.programmedUnits, 2.0)
        XCTAssertEqual(dose.automatic, false)
        XCTAssertFalse(dose.manuallyEntered)
        XCTAssertTrue(dose.wasProgrammedByPumpUI)

        report(start + [completion])
        XCTAssertEqual(reportedBoluses.count, 1, "A re-read of the same history reports nothing new")
    }

    func testInFlightPumpBolusIsReportedOnlyOnceItsCompletionIsRead() throws {
        let start = quickBolusStart(bolusId: 43, units: 0.5, firstSequenceNum: 200, secondsAgo: 60)
        report(start)

        XCTAssertTrue(delegate.pumpEventBatches.isEmpty)
        XCTAssertNil(manager.state.bolusReportLedger.entry(bolusId: 43, pumpSerial: Self.pumpSerial))

        report(start + [bolusCompletion(bolusId: 43, delivered: 0.45, requested: 0.5, sequenceNum: 203, secondsAgo: 45)])

        let event = try XCTUnwrap(reportedBoluses.first)
        XCTAssertEqual(reportedBoluses.count, 1)
        XCTAssertEqual(delegate.pumpEventBatches.last?.replacePendingEvents, false)
        XCTAssertEqual(event.raw, HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: 43))
        XCTAssertEqual(event.date, pumpDate(start[1]))
        XCTAssertEqual(event.dose?.isMutable, false)
        XCTAssertEqual(event.dose?.deliveredUnits, 0.45)
        XCTAssertEqual(manager.state.bolusReportLedger.entry(bolusId: 43, pumpSerial: Self.pumpSerial)?.isFinalized, true)
    }

    func testAPumpBolusReportedInFlightByAnEarlierBuildIsFinalizedInAReplacingBatch() throws {
        let start = quickBolusStart(bolusId: 46, units: 1.0, firstSequenceNum: 210, secondsAgo: 60)
        let raw = HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: 46)
        manager.state.bolusReportLedger.record(BolusReportLedger.Entry(
            bolusId: 46,
            pumpSerial: Self.pumpSerial,
            origin: .history,
            raw: raw,
            eventDate: pumpDate(start[1]),
            automatic: false,
            isFinalized: false
        ))

        report(start + [bolusCompletion(bolusId: 46, delivered: 1.0, requested: 1.0, sequenceNum: 213, secondsAgo: 30)])

        let batch = try XCTUnwrap(delegate.pumpEventBatches.last)
        XCTAssertTrue(batch.replacePendingEvents)
        XCTAssertEqual(batch.events.first { $0.raw == raw }?.dose?.isMutable, false)
    }

    // MARK: - What Loop ends up holding

    private func feedLoop() -> LoopDoseStoreOracle {
        let loop = LoopDoseStoreOracle()
        for batch in delegate.pumpEventBatches {
            loop.addPumpEvents(
                batch.events,
                lastReconciliation: batch.lastReconciliation,
                replacePendingEvents: batch.replacePendingEvents,
                now: Date()
            )
        }
        return loop
    }

    private func runTempBasal() {
        manager.state.basalDose = UnfinalizedDose(
            tempRate: 1.5,
            duration: .minutes(30),
            automatic: true,
            insulinType: nil,
            startDate: now.addingTimeInterval(-.minutes(10))
        )
    }

    /// The field report on #452: first seen 2 s into delivery, finished a tick later, then a temp basal.
    func testLoopKeepsAPumpBolusFirstSeenInFlight() throws {
        manager.state.lastReconciliation = now
        // A batch with no dose that outlasts reconciliation never reaches InsulinDeliveryStore.
        runTempBasal()
        let start = quickBolusStart(bolusId: 91, units: 1.0, firstSequenceNum: 290, secondsAgo: 30)
        report(start)
        report(start + [bolusCompletion(bolusId: 91, delivered: 1.0, requested: 1.0, sequenceNum: 293, secondsAgo: 2)])
        let raw = try XCTUnwrap(reportedBoluses.last?.raw)

        manager.startScheduledBasalDose()
        manager.waitForDelegateCalls()

        let stored = try XCTUnwrap(feedLoop().assertPermanent(raw: raw))
        XCTAssertEqual(stored.dose.deliveredUnits, 1.0)
    }

    func testLoopFinalizesAPumpBolusAnEarlierBuildReportedInFlight() throws {
        manager.state.lastReconciliation = now
        runTempBasal()
        let start = quickBolusStart(bolusId: 92, units: 1.0, firstSequenceNum: 300, secondsAgo: 30)
        let raw = HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: 92)
        let date = pumpDate(start[1])
        manager.state.bolusReportLedger.record(BolusReportLedger.Entry(
            bolusId: 92,
            pumpSerial: Self.pumpSerial,
            origin: .history,
            raw: raw,
            eventDate: date,
            automatic: false,
            isFinalized: false
        ))
        let inFlight = DoseEntry(type: .bolus, startDate: date, value: 1.0, unit: .units, doseId: nil, isMutable: true)
        manager.emitPumpEvents(
            [NewPumpEvent(date: date, dose: inFlight, raw: raw, title: "Bolus", type: .bolus)],
            replacePendingEvents: false
        )

        report(start + [bolusCompletion(bolusId: 92, delivered: 0.75, requested: 1.0, sequenceNum: 303, secondsAgo: 2)])

        let stored = try XCTUnwrap(feedLoop().assertPermanent(raw: raw))
        XCTAssertEqual(stored.dose.deliveredUnits, 0.75)
    }

    func testControlIQBolusIsReportedAsAutomatic() throws {
        let activation = BolusActivatedHistoryLog(
            pumpTimeSec: nowPumpTimeSec - 120,
            sequenceNum: 300,
            bolusId: 44,
            selectedIob: 0,
            iob: 0,
            bolusSize: 0.3
        )
        let delivery = BolusDeliveryHistoryLog(
            pumpTimeSec: nowPumpTimeSec - 120,
            sequenceNum: 301,
            bolusID: 44,
            bolusDeliveryStatus: 1,
            bolusTypeBitmask: 8,
            bolusSource: BolusDeliveryHistoryLog.BolusSource.controlIQAutoBolus.rawValue,
            remoteId: 0,
            requestedNow: 300,
            requestedLater: 0,
            correction: 300,
            extendedDurationRequested: 0,
            deliveredTotal: 0
        )

        report([activation, delivery, bolusCompletion(bolusId: 44, delivered: 0.3, requested: 0.3, sequenceNum: 302, secondsAgo: 110)])

        XCTAssertEqual(try XCTUnwrap(reportedBoluses.first?.dose).automatic, true)
    }

    // MARK: - App-commanded boluses

    func testAppBolusAlreadyFinalizedLiveIsNotReportedAgain() {
        manager.state.bolusReportLedger.record(commandedEntry(bolusId: 50, isFinalized: true))

        report(quickBolusStart(bolusId: 50, units: 1.0, firstSequenceNum: 400, secondsAgo: 600)
            + [bolusCompletion(bolusId: 50, delivered: 1.0, requested: 1.0, sequenceNum: 403, secondsAgo: 560)])

        XCTAssertTrue(delegate.pumpEventBatches.isEmpty)
    }

    func testAppBolusStillRunningIsLeftToTheLivePath() {
        manager.state.bolusReportLedger.record(commandedEntry(bolusId: 51, isFinalized: false))
        let dose = UnfinalizedDose(
            units: 1.0,
            duration: 60,
            activationType: .manualNoRecommendation,
            insulinType: nil,
            bolusId: 51,
            now: now.addingTimeInterval(-600)
        )
        manager.state.bolusDose = dose
        manager.bolusProgressReport = TandemDoseProgressReporter(
            pumpManager: manager,
            dose: dose.toDoseEntry(isMutable: true),
            activationType: .manualNoRecommendation
        )

        report(quickBolusStart(bolusId: 51, units: 1.0, firstSequenceNum: 500, secondsAgo: 600)
            + [bolusCompletion(bolusId: 51, delivered: 1.0, requested: 1.0, sequenceNum: 503, secondsAgo: 560)])

        XCTAssertTrue(delegate.pumpEventBatches.isEmpty)
        XCTAssertNotNil(manager.state.bolusDose)
    }

    func testAppBolusLeftUnfinalizedIsFinalizedUnderItsLiveIdentity() throws {
        let entry = commandedEntry(bolusId: 52, isFinalized: false)
        manager.state.bolusReportLedger.record(entry)
        let pending = UnfinalizedDose(
            units: 1.0,
            duration: 60,
            activationType: .manualNoRecommendation,
            insulinType: nil,
            bolusId: 52,
            now: entry.eventDate
        )
        manager.state.pendingBolusFinalization = pending

        report(quickBolusStart(bolusId: 52, units: 1.0, firstSequenceNum: 600, secondsAgo: 600)
            + [bolusCompletion(bolusId: 52, delivered: 0.65, requested: 1.0, sequenceNum: 603, secondsAgo: 570)])

        let event = try XCTUnwrap(reportedBoluses.first)
        XCTAssertEqual(reportedBoluses.count, 1)
        XCTAssertEqual(event.raw, entry.raw)
        XCTAssertEqual(event.date, entry.eventDate)
        XCTAssertEqual(event.dose?.syncIdentifier, entry.raw.hexadecimalString)
        XCTAssertEqual(event.dose?.deliveredUnits, 0.65)
        XCTAssertEqual(event.dose?.isMutable, false)
        XCTAssertEqual(event.dose?.wasProgrammedByPumpUI, false)
        XCTAssertEqual(delegate.pumpEventBatches.last?.replacePendingEvents, true)
        XCTAssertNil(manager.state.pendingBolusFinalization)
        XCTAssertEqual(manager.state.bolusReportLedger.entry(bolusId: 52, pumpSerial: Self.pumpSerial)?.isFinalized, true)
    }

    func testAppBolusFinalizedFromHistoryKeepsItsDecision() throws {
        let decisionId = UUID()
        let entry = commandedEntry(bolusId: 52, isFinalized: false, decisionId: decisionId)
        manager.state.bolusReportLedger.record(entry)

        report(quickBolusStart(bolusId: 52, units: 1.0, firstSequenceNum: 600, secondsAgo: 600)
            + [bolusCompletion(bolusId: 52, delivered: 0.65, requested: 1.0, sequenceNum: 603, secondsAgo: 570)])

        let event = try XCTUnwrap(reportedBoluses.first)
        XCTAssertEqual(event.dose?.isMutable, false)
        XCTAssertEqual(event.dose?.decisionId, decisionId)
    }

    func testABolusDecisionSurvivesARelaunchInTheLedger() throws {
        let entry = commandedEntry(bolusId: 52, isFinalized: false, decisionId: UUID())

        XCTAssertEqual(try XCTUnwrap(BolusReportLedger.Entry(rawValue: entry.rawValue)), entry)
    }

    func testALedgerEntrySavedWithoutADecisionStillDecodes() throws {
        var raw = commandedEntry(bolusId: 52, isFinalized: false).rawValue
        raw["decisionId"] = nil

        XCTAssertNil(try XCTUnwrap(BolusReportLedger.Entry(rawValue: raw)).decisionId)
    }

    func testAppBolusOrphanedByARelaunchIsFinalizedAndReleased() throws {
        manager.state.bolusReportLedger.record(commandedEntry(bolusId: 53, isFinalized: false))
        manager.state.bolusDose = UnfinalizedDose(
            units: 1.0,
            duration: 60,
            activationType: .manualNoRecommendation,
            insulinType: nil,
            bolusId: 53,
            now: now.addingTimeInterval(-600)
        )
        manager.state.bolusState = .inProgress(manager.state.bolusDose!.toDoseEntry(isMutable: true))

        report(quickBolusStart(bolusId: 53, units: 1.0, firstSequenceNum: 700, secondsAgo: 600)
            + [bolusCompletion(bolusId: 53, delivered: 1.0, requested: 1.0, sequenceNum: 703, secondsAgo: 570)])

        XCTAssertEqual(reportedBoluses.count, 1)
        XCTAssertNil(manager.state.bolusDose)
        guard case .noBolus = manager.state.bolusState else {
            return XCTFail("Expected noBolus, got \(manager.state.bolusState)")
        }
    }

    func testLiveFinalizationIsRecordedInTheLedger() {
        let entry = commandedEntry(bolusId: 54, isFinalized: false)
        manager.state.bolusReportLedger.record(entry)
        let finalized = NewPumpEvent(
            date: entry.eventDate,
            dose: DoseEntry(type: .bolus, startDate: entry.eventDate, value: 1.0, unit: .units, doseId: nil, deliveredUnits: 1.0),
            raw: entry.raw,
            title: "Bolus"
        )

        manager.emitPumpEvents([finalized])

        XCTAssertEqual(manager.state.bolusReportLedger.entry(bolusId: 54, pumpSerial: Self.pumpSerial)?.isFinalized, true)
    }

    // MARK: - Pump clock

    private func setPumpClock(ahead offset: UInt32) {
        pumpClockAhead = offset
        manager.state.lastPumpTimeCheckDate = now
        manager.state.currentPumpTime = now.addingTimeInterval(TimeInterval(offset))
    }

    func testAPumpBolusIsDatedOnThePhonesClock() throws {
        setPumpClock(ahead: 3 * 3600)
        let start = quickBolusStart(bolusId: 44, units: 1.0, firstSequenceNum: 300, secondsAgo: 300)
        let completion = bolusCompletion(bolusId: 44, delivered: 1.0, requested: 1.0, sequenceNum: 303, secondsAgo: 240)

        report(start + [completion])

        let event = try XCTUnwrap(reportedBoluses.first)
        XCTAssertEqual(event.date, pumpDate(start[1]).addingTimeInterval(-.hours(3)))
        XCTAssertEqual(event.dose?.endDate, pumpDate(completion).addingTimeInterval(-.hours(3)))
    }

    func testAPumpBolusIsFlooredOnThePhonesClock() {
        setPumpClock(ahead: 3600)
        let secondsAgo = UInt32(2.5 * 3600)
        let logs = quickBolusStart(bolusId: 45, units: 1.0, firstSequenceNum: 400, secondsAgo: secondsAgo)
            + [bolusCompletion(bolusId: 45, delivered: 1.0, requested: 1.0, sequenceNum: 403, secondsAgo: secondsAgo - 60)]

        report(logs, floor: now.addingTimeInterval(-.hours(2)))

        XCTAssertTrue(delegate.pumpEventBatches.isEmpty, "Its pump stamp is past the floor; the instant it was given is not")
    }

    // MARK: - Floors and gating

    func testBolusBeforeTheLedgerStartedTrackingIsNotReported() {
        let logs = quickBolusStart(bolusId: 60, units: 1.0, firstSequenceNum: 800, secondsAgo: 3600)
            + [bolusCompletion(bolusId: 60, delivered: 1.0, requested: 1.0, sequenceNum: 803, secondsAgo: 3560)]

        report(logs, floor: now.addingTimeInterval(-1800))

        XCTAssertTrue(delegate.pumpEventBatches.isEmpty)
    }

    /// The unexplained second report on #452.
    func testAnAppBolusAgingOutOfTheHorizonIsNotReportedAgain() {
        let secondsAgo = UInt32(BolusReportLedger.reportingHorizon) + 5
        // Dated at programming, past the horizon; history dates it at activation, 14 s later, inside it.
        manager.state.bolusReportLedger.record(BolusReportLedger.Entry(
            bolusId: 63,
            pumpSerial: Self.pumpSerial,
            origin: .commanded,
            raw: Data("bolus 1.0 live".utf8),
            eventDate: now.addingTimeInterval(-TimeInterval(secondsAgo)),
            automatic: false,
            isFinalized: true
        ))

        report(quickBolusStart(bolusId: 63, units: 1.0, firstSequenceNum: 1100, secondsAgo: secondsAgo)
            + [bolusCompletion(bolusId: 63, delivered: 1.0, requested: 1.0, sequenceNum: 1103, secondsAgo: secondsAgo - 44)])

        XCTAssertTrue(delegate.pumpEventBatches.isEmpty)
    }

    func testNothingIsReportedWithoutTheFlag() {
        manager.state.featureFlags[.historyDoseReporting] = false
        let logs = quickBolusStart(bolusId: 61, units: 1.0, firstSequenceNum: 900, secondsAgo: 300)
        manager.storeHistoryLogs(logs, now: now)

        manager.reportHistoryDoses(
            after: HistoryBackfillCoordinator.TickOutcome(
                bookkeeping: HistoryBackfillState(pumpSerial: Self.pumpSerial, watermark: 902),
                rangesRead: [900 ... 902],
                sessionCovered: 900 ... 902,
                isDeepBackfillComplete: true,
                emitFloor: .distantPast
            ),
            now: now
        )
        manager.waitForDelegateCalls()

        XCTAssertTrue(delegate.pumpEventBatches.isEmpty)
    }

    func testAReportedBolusIsNotReportedAgainAfterARelaunch() {
        let logs = quickBolusStart(bolusId: 62, units: 1.0, firstSequenceNum: 1000, secondsAgo: 300)
            + [bolusCompletion(bolusId: 62, delivered: 1.0, requested: 1.0, sequenceNum: 1003, secondsAgo: 260)]
        report(logs)
        XCTAssertEqual(reportedBoluses.count, 1)

        let relaunched = TandemPumpManagerState(rawValue: manager.state.rawValue)
        manager = makeManager(state: relaunched)
        report(logs)

        XCTAssertTrue(reportedBoluses.isEmpty)
    }

    func testLedgerRoundTripsThroughRawValue() {
        var ledger = BolusReportLedger(trackingSince: Date(timeIntervalSinceReferenceDate: 1000))
        ledger.record(commandedEntry(bolusId: 70, isFinalized: true))
        ledger.record(BolusReportLedger.Entry(
            bolusId: 71,
            pumpSerial: nil,
            origin: .history,
            raw: Data([1, 2, 3]),
            eventDate: Date(timeIntervalSinceReferenceDate: 2000),
            automatic: true,
            isFinalized: false
        ))

        ledger.noteUnreported(BolusReportLedger.UnreportedBolus(
            bolusId: 72,
            pumpSerial: Self.pumpSerial,
            startDate: Date(timeIntervalSinceReferenceDate: 3000),
            holdsBoundaryAt: Date(timeIntervalSinceReferenceDate: 3010)
        ))

        XCTAssertEqual(BolusReportLedger(rawValue: ledger.rawValue), ledger)
    }

    // MARK: - The boundary at a pump bolus the app did not start

    private func stubBolusDelivering(bolusId: Int, secondsAgo: UInt32) {
        bluetooth.stub(CurrentBolusStatusRequest.self, with: CurrentBolusStatusResponse(
            statusId: CurrentBolusStatusResponse.CurrentBolusStatus.delivering.rawValue,
            bolusId: bolusId,
            timestamp: nowPumpTimeSec - secondsAgo,
            requestedVolume: 2000,
            bolusSourceId: BolusSource.quickBolus.rawValue,
            bolusTypeBitmask: 1
        ))
    }

    private func pumpDate(secondsAgo: UInt32) -> Date {
        Dates.fromJan12008EpochSecondsToDate(TimeInterval(nowPumpTimeSec - secondsAgo))
    }

    @discardableResult
    private func reportBoundary() -> Date? {
        manager.reportReconciliationBoundary()
        manager.waitForDelegateCalls()
        return delegate.pumpEventBatches.last?.lastReconciliation
    }

    func testAPumpBolusSeenDeliveringHoldsTheBoundaryUntilHistoryReportsIt() throws {
        manager.state.lastReconciliation = now.addingTimeInterval(-600)
        stubBolusDelivering(bolusId: 42, secondsAgo: 20)

        manager.fetchBolusStatus(fromSync: false)
        manager.state.lastReconciliation = now

        XCTAssertEqual(manager.state.bolusReportLedger.boundaryHold(pumpSerial: Self.pumpSerial), pumpDate(secondsAgo: 20))
        XCTAssertEqual(reportBoundary(), pumpDate(secondsAgo: 20))

        let start = quickBolusStart(bolusId: 42, units: 2.0, firstSequenceNum: 100, secondsAgo: 34)
        report(start + [bolusCompletion(bolusId: 42, delivered: 2.0, requested: 2.0, sequenceNum: 103, secondsAgo: 5)])

        let batch = try XCTUnwrap(delegate.pumpEventBatches.last)
        XCTAssertEqual(batch.events.map(\.raw), [HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: 42)])
        XCTAssertEqual(batch.lastReconciliation, now, "released by the batch that reports it")
        XCTAssertNil(manager.state.bolusReportLedger.boundaryHold(pumpSerial: Self.pumpSerial))
    }

    func testAHeldBoundaryNeverMovesBackward() {
        manager.state.lastReconciliation = now
        stubBolusDelivering(bolusId: 42, secondsAgo: 120)

        manager.fetchBolusStatus(fromSync: false)
        manager.state.lastReconciliation = now.addingTimeInterval(300)

        XCTAssertEqual(reportBoundary(), now)
    }

    func testAPumpBolusDoesNotHoldTheBoundaryWithHistoryDoseReportingOff() {
        manager.state.featureFlags[.historyDoseReporting] = false
        manager.state.lastReconciliation = now.addingTimeInterval(-600)
        stubBolusDelivering(bolusId: 42, secondsAgo: 20)

        manager.fetchBolusStatus(fromSync: false)
        manager.state.lastReconciliation = now

        XCTAssertTrue(manager.state.bolusReportLedger.unreported.isEmpty)
        XCTAssertEqual(reportBoundary(), now)
    }

    func testTheAppsOwnBolusDoesNotHoldTheBoundary() {
        manager.state.bolusReportLedger.record(commandedEntry(bolusId: 42, isFinalized: false))
        stubBolusDelivering(bolusId: 42, secondsAgo: 20)

        manager.fetchBolusStatus(fromSync: false)

        XCTAssertNil(manager.state.bolusReportLedger.boundaryHold(pumpSerial: Self.pumpSerial))
    }

    func testAPumpBolusFromBeforeTrackingBeganDoesNotHoldTheBoundary() {
        manager.state.bolusReportLedger = BolusReportLedger(trackingSince: now)
        stubBolusDelivering(bolusId: 42, secondsAgo: 20)

        manager.fetchBolusStatus(fromSync: false)

        XCTAssertNil(manager.state.bolusReportLedger.boundaryHold(pumpSerial: Self.pumpSerial))
    }

    func testAHoldIsDroppedOncePastTheReportingHorizon() {
        let start = now.addingTimeInterval(-BolusReportLedger.reportingHorizon - 60)
        var ledger = BolusReportLedger(trackingSince: .distantPast)
        ledger.noteUnreported(BolusReportLedger.UnreportedBolus(bolusId: 42, pumpSerial: Self.pumpSerial, startDate: start, holdsBoundaryAt: start))

        ledger.prune(now: now)

        XCTAssertNil(ledger.boundaryHold(pumpSerial: Self.pumpSerial))
    }

    func testABolusSeenOnAnotherPumpDoesNotHoldTheBoundary() {
        manager.state.lastReconciliation = now.addingTimeInterval(-600)
        stubBolusDelivering(bolusId: 42, secondsAgo: 20)
        manager.fetchBolusStatus(fromSync: false)

        manager.state.pumpState.pumpSerial = Self.pumpSerial + 1
        manager.state.lastReconciliation = now

        XCTAssertEqual(reportBoundary(), now)
    }

    func testAHoldSurvivesARelaunch() {
        manager.state.lastReconciliation = now.addingTimeInterval(-600)
        stubBolusDelivering(bolusId: 42, secondsAgo: 20)
        manager.fetchBolusStatus(fromSync: false)

        manager = makeManager(state: TandemPumpManagerState(rawValue: manager.state.rawValue))
        manager.state.lastReconciliation = now

        XCTAssertEqual(reportBoundary(), pumpDate(secondsAgo: 20))
    }

    func testLoopKeepsAPumpBolusTheBoundaryWasHeldFor() throws {
        manager.state.lastReconciliation = now.addingTimeInterval(-600)
        stubBolusDelivering(bolusId: 42, secondsAgo: 20)
        manager.fetchBolusStatus(fromSync: false)
        manager.state.lastReconciliation = now
        reportBoundary()

        let start = quickBolusStart(bolusId: 42, units: 2.0, firstSequenceNum: 100, secondsAgo: 34)
        report(start + [bolusCompletion(bolusId: 42, delivered: 2.0, requested: 2.0, sequenceNum: 103, secondsAgo: 5)])

        let loop = feedLoop()
        let stored = try XCTUnwrap(loop.assertPermanent(raw: HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: 42)))
        XCTAssertEqual(stored.dose.deliveredUnits, 2.0)
        XCTAssertEqual(loop.lastReconciliation, now)
    }

    // MARK: - A sync waits for history when the pump can bolus on its own

    func testASyncWaitsForHistoryOnlyWhenThePumpCanBolusOnItsOwn() {
        manager.state.quickBolusEnabled = false
        XCTAssertFalse(manager.awaitsHistoryBoluses)

        manager.state.useControlIQ = true
        XCTAssertTrue(manager.awaitsHistoryBoluses)

        manager.state.useControlIQ = false
        manager.state.quickBolusEnabled = nil
        XCTAssertTrue(manager.awaitsHistoryBoluses, "not yet read as off")

        manager.state.featureFlags[.historyDoseReporting] = false
        XCTAssertFalse(manager.awaitsHistoryBoluses)
    }

    private func sync(timeout: TimeInterval = 90, then check: @escaping () -> Void = {}) {
        bluetooth.stub(InsulinStatusRequest.self, with: InsulinStatusResponse(currentInsulinAmount: 150, isEstimate: 0, insulinLowAmount: 20))
        let synced = expectation(description: "syncPumpData completes")
        manager.syncPumpData { _ in
            check()
            synced.fulfill()
        }
        wait(for: [synced], timeout: timeout)
        manager.waitForDelegateCalls()
    }

    func testASyncUnderControlIQCompletesOnlyOnceHistoryHasReportedAPumpBolus() {
        manager.state.useControlIQ = true
        manager.state.quickBolusEnabled = false
        stubPump(serving: quickBolusStart(bolusId: 80, units: 2.0, firstSequenceNum: 1, secondsAgo: 300)
            + [bolusCompletion(bolusId: 80, delivered: 2.0, requested: 2.0, sequenceNum: 4, secondsAgo: 240)])

        var reportedFirst: Bool?
        sync { reportedFirst = self.manager.state.bolusReportLedger.entry(bolusId: 80, pumpSerial: Self.pumpSerial)?.isFinalized }

        XCTAssertEqual(reportedFirst, true)
    }

    func testASyncDoesNotWaitForHistoryWhenThePumpCannotBolusOnItsOwn() {
        manager.state.quickBolusEnabled = false
        // Acknowledges the read and never streams: a tick that cannot finish.
        bluetooth.stub(HistoryLogStatusRequest.self, with: HistoryLogStatusResponse(numEntries: 4, firstSequenceNum: 1, lastSequenceNum: 4))
        bluetooth.stub(HistoryLogRequest.self, with: HistoryLogResponse(status: 0, streamId: 7))

        let began = Date()
        sync()

        XCTAssertLessThan(Date().timeIntervalSince(began), 1)
    }

    func testAFailedHistoryReadReleasesAWaitingSync() {
        manager.state.quickBolusEnabled = true
        manager.transitionHistoryWait = .seconds(30)

        let began = Date()
        sync()

        XCTAssertLessThan(Date().timeIntervalSince(began), 10)
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

    private func runTick() {
        let ticked = expectation(description: "backfill tick completes")
        manager.historyBackfillCoordinator.runTick(now: now) { _ in ticked.fulfill() }
        wait(for: [ticked], timeout: 90.0)
        manager.waitForDelegateCalls()
    }

    func testABackfillTickReportsAPumpBolusItRead() throws {
        stubPump(serving: quickBolusStart(bolusId: 80, units: 2.0, firstSequenceNum: 1, secondsAgo: 300)
            + [bolusCompletion(bolusId: 80, delivered: 2.0, requested: 2.0, sequenceNum: 4, secondsAgo: 240)])

        runTick()

        let event = try XCTUnwrap(reportedBoluses.first)
        XCTAssertEqual(reportedBoluses.count, 1)
        XCTAssertEqual(event.raw, HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: 80))
        XCTAssertEqual(event.dose?.deliveredUnits, 2.0)
    }

    func testATickRequestedWhileOneRunsIsRunAfterIt() {
        stubPump(serving: quickBolusStart(bolusId: 81, units: 1.0, firstSequenceNum: 1, secondsAgo: 300))

        let first = expectation(description: "first tick completes")
        manager.historyBackfillCoordinator.runTick(now: now) { _ in first.fulfill() }
        let overlapping = expectation(description: "overlapping request returns at once")
        manager.historyBackfillCoordinator.runTick(now: now) { outcome in
            XCTAssertNil(outcome)
            overlapping.fulfill()
        }
        wait(for: [overlapping, first], timeout: 90.0)

        // The first tick reads its range with two status reads (its own and the fetcher's); the
        // re-run finds nothing new and makes one.
        let deadline = Date().addingTimeInterval(30)
        while bluetooth.sent(HistoryLogStatusRequest.self).count < 3, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(bluetooth.sent(HistoryLogStatusRequest.self).count, 3, "The dropped request runs once the first tick ends")
    }

    // MARK: - Shelf mode

    /// The pump's previous use, a ShelfMode record, its clock restarted at 2008, then setup's clock write,
    /// whose change would put the old bolus decades ahead.
    private func historyAcrossShelfMode() -> [HistoryLog] {
        let previousUse = nowPumpTimeSec - UInt32(TimeInterval.days(200))
        let written = nowPumpTimeSec - 600
        let restarted: UInt32 = 1000
        return quickBolusStart(bolusId: 70, units: 2.0, firstSequenceNum: 1, secondsAgo: nowPumpTimeSec - previousUse)
            + [
                bolusCompletion(bolusId: 70, delivered: 2.0, requested: 2.0, sequenceNum: 4, secondsAgo: nowPumpTimeSec - previousUse - 60),
                ShelfModeHistoryLog(
                    pumpTimeSec: previousUse + 3600,
                    sequenceNum: 5,
                    msecSinceReset: 0,
                    lipoIbc: 0,
                    lipoAbc: 0,
                    lipoCurrent: 0,
                    lipoRemCap: 0,
                    lipoMv: 0
                ),
                // Stamped on the clock it set, the restarted time of day on the new date.
                DateChangeHistoryLog(pumpTimeSec: written / 86400 * 86400 + restarted, sequenceNum: 6, datePrior: 0, dateAfter: written / 86400, rawRTCTime: 0),
                TimeChangedHistoryLog(
                    pumpTimeSec: written,
                    sequenceNum: 7,
                    timePrior: restarted * 1000,
                    timeAfter: (written % 86400) * 1000,
                    rawRTC: 0
                ),
            ]
            + quickBolusStart(bolusId: 71, units: 1.0, firstSequenceNum: 8, secondsAgo: 300)
            + [bolusCompletion(bolusId: 71, delivered: 1.0, requested: 1.0, sequenceNum: 11, secondsAgo: 240)]
    }

    func testABolusFromBeforeShelfModeIsNotReportedAndOneAfterTheClockWriteIs() throws {
        stubPump(serving: historyAcrossShelfMode())

        runTick()

        XCTAssertEqual(manager.state.historyBackfill?.undatableThroughSequenceNum, 5)
        XCTAssertEqual(reportedBoluses.map(\.raw), [HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: 71)])
        XCTAssertNil(manager.state.bolusReportLedger.entry(bolusId: 70, pumpSerial: Self.pumpSerial))
    }

    func testABolusFromBeforeShelfModeStaysUnreportedAfterARelaunch() throws {
        stubPump(serving: historyAcrossShelfMode())
        runTick()

        let readBefore = bluetooth.sent(HistoryLogRequest.self).count
        manager = makeManager(state: manager.state)
        stubPump(serving: historyAcrossShelfMode())
        runTick()

        XCTAssertFalse(reportedBoluses.contains { $0.raw == HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: 70) })
        let reads = bluetooth.sent(HistoryLogRequest.self).dropFirst(readBefore)
        XCTAssertFalse(reads.isEmpty)
        XCTAssertTrue(
            reads.allSatisfy { Int($0.startLog) - max($0.numberOfLogs, 1) + 1 > 5 },
            "read at or below the ShelfMode record after a relaunch: \(reads.map { ($0.startLog, $0.numberOfLogs) })"
        )
    }

    // MARK: - Dating by the pump's clock

    private func reportedBolus(_ bolusId: Int) -> NewPumpEvent? {
        reportedBoluses.first { $0.raw == HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: bolusId) }
    }

    private func pumpBolus(_ bolusId: Int, firstSequenceNum: UInt32, secondsAgo: UInt32 = 300) -> [HistoryLog] {
        quickBolusStart(bolusId: bolusId, units: 1.0, firstSequenceNum: firstSequenceNum, secondsAgo: secondsAgo)
            + [bolusCompletion(bolusId: bolusId, delivered: 1.0, requested: 1.0, sequenceNum: firstSequenceNum + 3, secondsAgo: secondsAgo - 60)]
    }

    private func anchor(_ sequenceNum: UInt32, secondsAgo: TimeInterval = 0, pumpAhead: Int = 0) -> PumpClockAnchor {
        PumpClockAnchor(
            sequenceNum: sequenceNum,
            pumpTimeSec: UInt32(Int(phoneNowPumpTimeSec) - Int(secondsAgo) + pumpAhead),
            phoneDate: now.addingTimeInterval(-secondsAgo)
        )
    }

    func testABolusOnAPumpClockTwoDaysAheadIsReportedWhenThePumpGaveItAndEnded() throws {
        setPumpClock(ahead: 2 * 86400)

        report(pumpBolus(72, firstSequenceNum: 900))

        let dose = try XCTUnwrap(reportedBolus(72)?.dose)
        XCTAssertEqual(dose.startDate.timeIntervalSince(now), -286, accuracy: 2)
        XCTAssertEqual(dose.endDate.timeIntervalSince(now), -240, accuracy: 2)
        XCTAssertTrue(manager.state.heldHistory.entries.isEmpty)
    }

    func testABolusOnAPumpClockTwoDaysBehindIsReportedWhenThePumpGaveIt() throws {
        manager.state.pumpClockAnchors.record(anchor(910, pumpAhead: -2 * 86400), pumpSerial: Self.pumpSerial)

        report(pumpBolus(73, firstSequenceNum: 900, secondsAgo: 2 * 86400 + 300))

        let dose = try XCTUnwrap(reportedBolus(73)?.dose)
        XCTAssertEqual(dose.startDate.timeIntervalSince(now), -286, accuracy: 2)
    }

    func testAHistoryBolusStampedAheadOfThePumpsClockIsHeldNotReported() {
        // Stamped two hours ahead of a pump clock the manager reads as matching the phone's.
        pumpClockAhead = 7200

        report(pumpBolus(74, firstSequenceNum: 900))

        XCTAssertTrue(delegate.pumpEventBatches.isEmpty)
        XCTAssertNil(manager.state.bolusReportLedger.entry(bolusId: 74, pumpSerial: Self.pumpSerial), "unhandled, so a later pass can report it")
        XCTAssertEqual(manager.state.heldHistory.entries.map(\.raw), [HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: 74)])
    }

    func testABolusTheHostAlreadyCountsIsNotHeldWhenItsHistoryCannotBeDated() {
        manager.state.bolusReportLedger.record(commandedEntry(bolusId: 85, isFinalized: false))
        pumpClockAhead = 7200

        report(pumpBolus(85, firstSequenceNum: 900))

        XCTAssertTrue(delegate.pumpEventBatches.isEmpty, "not finalized from a record with no date")
        XCTAssertTrue(manager.state.heldHistory.entries.isEmpty)
    }

    func testAHeldBolusIsReportedAndLeavesTheHeldListOnceAPassDatesIt() throws {
        pumpClockAhead = 7200
        let logs = pumpBolus(75, firstSequenceNum: 900)
        report(logs)
        XCTAssertEqual(manager.state.heldHistory.entries.count, 1)

        manager.state.pumpClockAnchors.record(anchor(910, pumpAhead: 7200), pumpSerial: Self.pumpSerial)
        report(logs)

        let dose = try XCTUnwrap(reportedBolus(75)?.dose)
        XCTAssertEqual(dose.startDate.timeIntervalSince(now), -286, accuracy: 2)
        XCTAssertTrue(manager.state.heldHistory.entries.isEmpty)
    }

    func testBolusesEitherSideOfAClockJumpThePumpDidNotRecordAreEachReportedWhenGiven() throws {
        let jump = 3000 * 86400
        manager.state.pumpClockAnchors.record(anchor(899, secondsAgo: 1200), pumpSerial: Self.pumpSerial)
        manager.state.pumpClockAnchors.record(anchor(920, pumpAhead: jump), pumpSerial: Self.pumpSerial)
        pumpClockAhead = 0
        let before = pumpBolus(76, firstSequenceNum: 900, secondsAgo: 900)
        pumpClockAhead = UInt32(jump)
        let after = pumpBolus(77, firstSequenceNum: 910, secondsAgo: 300)

        report(before + after)

        XCTAssertEqual(try XCTUnwrap(reportedBolus(76)?.dose).startDate.timeIntervalSince(now), -886, accuracy: 2)
        XCTAssertEqual(try XCTUnwrap(reportedBolus(77)?.dose).startDate.timeIntervalSince(now), -286, accuracy: 2)
        XCTAssertTrue(manager.state.heldHistory.entries.isEmpty)
    }

    func testAHeldBolusRaisesAnAlertAfterFifteenMinutesAndRetractsItOnceDated() {
        // `now` is as old as the test run; the alert goes by the manager's clock.
        let now = manager.now
        let raw = HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: 78)
        manager.state.heldHistory.update(examined: [raw], held: [raw: 0], now: now.addingTimeInterval(-.minutes(14)))
        manager.reconcileHeldHistoryAlert()
        manager.waitForDelegateCalls()
        XCTAssertFalse(manager.isHistoryHeldTooLong)
        XCTAssertFalse(manager.state.heldHistoryAlertIssued)

        manager.state.heldHistory = HeldHistoryLedger()
        manager.state.heldHistory.update(examined: [raw], held: [raw: 0], now: now.addingTimeInterval(-.minutes(16)))
        manager.reconcileHeldHistoryAlert()
        manager.waitForDelegateCalls()
        delegate.waitForAlerts { !self.delegate.issuedAlerts.isEmpty }
        XCTAssertEqual(delegate.issuedAlerts.map(\.identifier.alertIdentifier), [TandemPumpManager.heldHistoryAlertIdentifier])
        XCTAssertTrue(manager.isHistoryHeldTooLong)

        manager.state.heldHistory.update(examined: [raw], held: [:], now: now)
        manager.reconcileHeldHistoryAlert()
        manager.waitForDelegateCalls()
        delegate.waitForAlerts { !self.delegate.retractedAlerts.isEmpty }
        XCTAssertEqual(delegate.retractedAlerts.map(\.alertIdentifier), [TandemPumpManager.heldHistoryAlertIdentifier])
    }

    // MARK: - The clock either side of a tick's history read

    private func outcome(reading logs: [HistoryLog], clock: HistoryBackfillCoordinator.TickOutcome.ClockRead) -> HistoryBackfillCoordinator.TickOutcome {
        manager.storeHistoryLogs(logs, now: now)
        let sequences = logs.map(\.sequenceNum)
        let range = sequences.min()! ... sequences.max()!
        return HistoryBackfillCoordinator.TickOutcome(
            bookkeeping: HistoryBackfillState(pumpSerial: Self.pumpSerial, watermark: range.upperBound),
            rangesRead: [range],
            sessionCovered: range,
            isDeepBackfillComplete: true,
            emitFloor: now.addingTimeInterval(-BolusReportLedger.reportingHorizon),
            startedAt: now,
            pumpSequenceRange: range,
            clock: clock
        )
    }

    private func reportAfterATick(reading logs: [HistoryLog], clock: HistoryBackfillCoordinator.TickOutcome.ClockRead) {
        manager.reportHistoryDoses(after: outcome(reading: logs, clock: clock), now: now)
        manager.waitForDelegateCalls()
    }

    func testATickWhoseClockReadsAgreeSavesItsAnchorAndDatesByIt() throws {
        let twoDays = 2 * 86400
        pumpClockAhead = UInt32(twoDays)
        bluetooth.stubPumpClock(ahead: TimeInterval(twoDays))

        reportAfterATick(reading: pumpBolus(79, firstSequenceNum: 900), clock: .anchor(anchor(903, pumpAhead: twoDays)))

        XCTAssertEqual(manager.state.pumpClockAnchors.anchors, [anchor(903, pumpAhead: twoDays)])
        XCTAssertEqual(try XCTUnwrap(reportedBolus(79)?.dose).startDate.timeIntervalSince(now), -286, accuracy: 2)
    }

    func testNothingIsDatedWhenThePumpsClockMovedWhileItsHistoryWasRead() {
        bluetooth.stubPumpClock(ahead: 3600)

        reportAfterATick(reading: pumpBolus(80, firstSequenceNum: 900), clock: .anchor(anchor(903)))

        XCTAssertTrue(delegate.pumpEventBatches.isEmpty)
        XCTAssertTrue(manager.state.pumpClockAnchors.anchors.isEmpty)
        XCTAssertNil(manager.state.bolusReportLedger.entry(bolusId: 80, pumpSerial: Self.pumpSerial))
        XCTAssertNotNil(manager.reconciliationLog.passes.last?.skipped)
    }

    func testNothingIsDatedWhenThePumpDoesNotGiveItsClockBeforeOrAfterItsHistory() {
        bluetooth.stub(TimeSinceResetRequest.self) { _ in nil }
        let logs = pumpBolus(81, firstSequenceNum: 900)

        reportAfterATick(reading: logs, clock: .unanswered)
        reportAfterATick(reading: logs, clock: .anchor(anchor(903)))

        XCTAssertTrue(delegate.pumpEventBatches.isEmpty)
        XCTAssertTrue(manager.state.pumpClockAnchors.anchors.isEmpty)
        XCTAssertEqual(manager.reconciliationLog.passes.filter { $0.skipped != nil }.count, 2)
    }

    func testAPassTheClockCheckSkippedReportsTheBolusOnTheNextTick() throws {
        let logs = pumpBolus(82, firstSequenceNum: 900)
        reportAfterATick(reading: logs, clock: .unanswered)
        XCTAssertNil(reportedBolus(82))

        reportAfterATick(reading: logs, clock: .anchor(anchor(903)))

        XCTAssertNotNil(reportedBolus(82))
    }

    func testABackfillTickReadsThePumpsClockBeforeAndAfterItsHistory() throws {
        bluetooth.stubPumpClock(ahead: 2 * 86400)
        pumpClockAhead = 2 * 86400
        stubPump(serving: pumpBolus(83, firstSequenceNum: 1))

        runTick()

        XCTAssertEqual(bluetooth.sent(TimeSinceResetRequest.self).count, 2)
        XCTAssertEqual(manager.state.pumpClockAnchors.anchors.map(\.sequenceNum), [4])
        XCTAssertEqual(try XCTUnwrap(reportedBolus(83)?.dose).startDate.timeIntervalSince(now), -286, accuracy: 3)
    }

    func testATickBegunRightAfterASyncsClockReadReadsTheClockOnceMore() throws {
        bluetooth.stubPumpClock()
        manager.fetchTimeSinceReset()
        stubPump(serving: pumpBolus(84, firstSequenceNum: 1))

        runTick()

        XCTAssertEqual(bluetooth.sent(TimeSinceResetRequest.self).count, 2, "the sync's read, and one after the history")
        XCTAssertNotNil(reportedBolus(84))
    }
}
