import LoopKit
@testable import TandemKit
import XCTest

/// An extended bolus programmed off the app reaches the host from pump history (#424): its up-front
/// part as any pump bolus, its extended part as a dose of its own, held mutable while it runs.
@available(macOS 13.0, iOS 14.0, *) final class ExtendedBolusReportingTests: XCTestCase {
    private static let pumpSerial: UInt32 = 123_456
    private let serial = HistoryLogSyncIdentifier.PumpSerial(ExtendedBolusReportingTests.pumpSerial)!

    private var bluetooth: StubPumpBluetooth!
    private var clock: ManualClock!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!

    // Whole seconds, so the pump's records land on it; in the past, as the oracles need.
    private let now = Date(timeIntervalSinceReferenceDate: Date().timeIntervalSinceReferenceDate.rounded(.down))
    private lazy var nowPumpTimeSec = UInt32(Dates.fromInstantToJan12008EpochSeconds(now))

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        clock = ManualClock(now)
        manager = makeManager(state: Self.reportingEnabledState())
    }

    override func tearDown() {
        manager = nil
        delegate = nil
        clock = nil
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
        let manager = TandemPumpManager(state: state, bluetooth: bluetooth, clock: clock)
        delegate = MockPumpManagerDelegate()
        manager.pumpManagerDelegate = delegate
        manager.waitForDelegateCalls()
        return manager
    }

    // MARK: - Fixtures

    /// The records the pump writes for an extended bolus programmed on its screen, `secondsAgo` before
    /// now: the up-front part first unless `upFront` is nil (100% extended), then its BolexActivated.
    /// Older t:slim X2 firmware writes no BolusDelivery records.
    private func extendedBolusStart(
        bolusId: Int,
        upFront: Float?,
        extended: Float,
        minutes: Int,
        bolusDeliveryRecords: Bool = true,
        firstSequenceNum: UInt32,
        secondsAgo: UInt32
    ) -> [HistoryLog] {
        let requested = nowPumpTimeSec - secondsAgo
        let activated = requested + 14
        var logs: [HistoryLog] = [
            BolusRequestedMsg2HistoryLog(
                pumpTimeSec: requested,
                sequenceNum: firstSequenceNum,
                bolusId: bolusId,
                options: BolusRequestedMsg2HistoryLog.BolusOption.extended.rawValue,
                standardPercent: upFront.map { Int(($0 / ($0 + extended) * 100).rounded()) } ?? 0,
                duration: minutes,
                spare1: 0,
                isf: 0,
                targetBG: 0,
                userOverride: false,
                declinedCorrection: false,
                selectedIOB: 0,
                spare2: 0
            )
        ]
        if bolusDeliveryRecords {
            logs.append(BolusDeliveryHistoryLog(
                pumpTimeSec: activated,
                sequenceNum: firstSequenceNum + 1,
                bolusID: bolusId,
                bolusDeliveryStatus: 1,
                bolusTypeBitmask: upFront == nil ? 2 : 3,
                bolusSource: BolusDeliveryHistoryLog.BolusSource.gui.rawValue,
                remoteId: bolusId & 0xFF,
                requestedNow: Int((upFront ?? 0) * 1000),
                requestedLater: Int(extended * 1000),
                correction: 0,
                extendedDurationRequested: minutes,
                deliveredTotal: 0
            ))
        }
        var bolexActivated = activated
        if let upFront {
            let upFrontCompleted = activated + 30
            logs += [
                BolusActivatedHistoryLog(
                    pumpTimeSec: activated,
                    sequenceNum: firstSequenceNum + UInt32(logs.count),
                    bolusId: bolusId,
                    selectedIob: 0,
                    iob: 0,
                    bolusSize: upFront
                ),
                BolusCompletedHistoryLog(
                    pumpTimeSec: upFrontCompleted,
                    sequenceNum: firstSequenceNum + UInt32(logs.count) + 1,
                    completionStatusId: 3,
                    bolusId: bolusId,
                    iob: upFront,
                    insulinDelivered: upFront,
                    insulinRequested: upFront
                )
            ]
            bolexActivated = upFrontCompleted
        }
        logs.append(BolexActivatedHistoryLog(
            pumpTimeSec: bolexActivated,
            sequenceNum: firstSequenceNum + UInt32(logs.count),
            bolusId: bolusId,
            iob: upFront ?? 0,
            bolexSize: extended
        ))
        return logs
    }

    private func bolexCompletion(
        bolusId: Int,
        delivered: Float,
        requested: Float,
        stoppedEarly: Bool = false,
        sequenceNum: UInt32,
        secondsAgo: UInt32
    ) -> BolexCompletedHistoryLog {
        BolexCompletedHistoryLog(
            pumpTimeSec: nowPumpTimeSec - secondsAgo,
            sequenceNum: sequenceNum,
            completionStatus: stoppedEarly ? 0 : 3,
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
        manager.storeHistoryLogs(logs, now: clock.now)
        let sequences = logs.map(\.sequenceNum)
        manager.reportHistoryBoluses(
            in: sequences.min()! ... sequences.max()!,
            pumpSerial: serial,
            floor: floor ?? clock.now.addingTimeInterval(-BolusReportLedger.reportingHorizon),
            now: clock.now
        )
        manager.waitForDelegateCalls()
    }

    private func reportPendingDoses() {
        manager.reportPendingDoses()
        manager.waitForDelegateCalls()
    }

    private func extendedRaw(_ bolusId: Int) -> Data {
        HistoryLogSyncIdentifier.extendedBolus(pumpSerial: serial, bolusId: bolusId)
    }

    private func events(raw: Data) -> [NewPumpEvent] {
        delegate.pumpEventBatches.flatMap(\.events).filter { $0.raw == raw }
    }

    private func feedLoop() -> LoopDoseStoreOracle {
        let loop = LoopDoseStoreOracle()
        for batch in delegate.pumpEventBatches {
            loop.addPumpEvents(batch.events, lastReconciliation: batch.lastReconciliation, replacePendingEvents: batch.replacePendingEvents, now: Date())
        }
        return loop
    }

    private func feedTrio() -> TrioDoseStoreOracle {
        let trio = TrioDoseStoreOracle()
        for batch in delegate.pumpEventBatches {
            trio.addPumpEvents(batch.events, lastReconciliation: batch.lastReconciliation, replacePendingEvents: batch.replacePendingEvents, now: Date())
        }
        return trio
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

    // MARK: - Finished before history read it

    func testAFullyExtendedBolusIsReportedOnceFinalizedFromItsCompletion() throws {
        let start = extendedBolusStart(bolusId: 30, upFront: nil, extended: 2.0, minutes: 30, firstSequenceNum: 100, secondsAgo: 3600)
        let completion = bolexCompletion(bolusId: 30, delivered: 2.0, requested: 2.0, sequenceNum: 103, secondsAgo: 3600 - 14 - 1800)

        report(start + [completion])

        XCTAssertEqual(delegate.pumpEventBatches.count, 1)
        XCTAssertEqual(delegate.pumpEventBatches.first?.replacePendingEvents, false)
        let event = try XCTUnwrap(events(raw: extendedRaw(30)).first)
        XCTAssertEqual(delegate.pumpEventBatches.flatMap(\.events).count, 1)
        XCTAssertEqual(event.type, .bolus)
        XCTAssertEqual(event.date, pumpDate(start[2]))
        let dose = try XCTUnwrap(event.dose)
        XCTAssertFalse(dose.isMutable)
        XCTAssertEqual(dose.startDate, pumpDate(start[2]))
        XCTAssertEqual(dose.endDate, pumpDate(completion))
        XCTAssertEqual(dose.programmedUnits, 2.0)
        XCTAssertEqual(dose.deliveredUnits, 2.0)
        XCTAssertEqual(dose.automatic, false)
        XCTAssertTrue(dose.wasProgrammedByPumpUI)
        XCTAssertEqual(manager.state.bolusReportLedger.entry(bolusId: 30, pumpSerial: Self.pumpSerial, part: .extended)?.isFinalized, true)

        report(start + [completion])
        XCTAssertEqual(delegate.pumpEventBatches.count, 1, "A re-read of the same history reports nothing new")
    }

    func testAnExtendedBolusIsReportedAsItsUpFrontPartAndItsExtendedPart() throws {
        let start = extendedBolusStart(bolusId: 31, upFront: 1.0, extended: 2.0, minutes: 60, firstSequenceNum: 200, secondsAgo: 7200)
        let completion = bolexCompletion(bolusId: 31, delivered: 2.0, requested: 2.0, sequenceNum: 205, secondsAgo: 7200 - 45 - 3600)

        report(start + [completion])

        let reported = delegate.pumpEventBatches.flatMap(\.events)
        XCTAssertEqual(reported.map(\.raw), [HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: 31), extendedRaw(31)])
        XCTAssertEqual(reported.map { $0.dose?.deliveredUnits }, [1.0, 2.0])
        XCTAssertEqual(reported.map { $0.dose?.isMutable }, [false, false])
        XCTAssertEqual(reported.last?.date, pumpDate(start[4]))
        XCTAssertEqual(manager.state.bolusReportLedger.reportedUnits(since: now.addingTimeInterval(-.hours(3))), 3.0, "Both parts count towards what the host was told")

        let trio = feedTrio()
        trio.assertNoDuplicates()
        XCTAssertEqual(trio.boluses.count, 2, "\(trio.boluses)")
    }

    func testAnExtendedPartStoppedEarlyIsReportedAtWhatItDelivered() throws {
        let start = extendedBolusStart(bolusId: 32, upFront: nil, extended: 2.0, minutes: 120, firstSequenceNum: 300, secondsAgo: 3600)
        let stop = bolexCompletion(bolusId: 32, delivered: 0.75, requested: 2.0, stoppedEarly: true, sequenceNum: 303, secondsAgo: 3600 - 14 - 2700)

        report(start + [stop])

        let dose = try XCTUnwrap(events(raw: extendedRaw(32)).first?.dose)
        XCTAssertFalse(dose.isMutable)
        XCTAssertEqual(dose.endDate, pumpDate(stop), "at the stop, not the programmed end")
        XCTAssertEqual(dose.programmedUnits, 2.0)
        XCTAssertEqual(dose.deliveredUnits, 0.75)
    }

    // MARK: - Running when history read it

    func testAnExtendedPartInFlightIsReportedMutableOverItsProgrammedDuration() throws {
        let start = extendedBolusStart(bolusId: 33, upFront: nil, extended: 3.0, minutes: 90, firstSequenceNum: 400, secondsAgo: 600)

        report(start)

        XCTAssertEqual(delegate.pumpEventBatches.last?.replacePendingEvents, false)
        let event = try XCTUnwrap(events(raw: extendedRaw(33)).first)
        let dose = try XCTUnwrap(event.dose)
        XCTAssertTrue(dose.isMutable)
        XCTAssertEqual(dose.startDate, pumpDate(start[2]))
        XCTAssertEqual(dose.endDate, pumpDate(start[2]).addingTimeInterval(.minutes(90)))
        XCTAssertEqual(dose.programmedUnits, 3.0)
        XCTAssertNil(dose.deliveredUnits)

        let entry = try XCTUnwrap(manager.state.bolusReportLedger.entry(bolusId: 33, pumpSerial: Self.pumpSerial, part: .extended))
        XCTAssertFalse(entry.isFinalized)
        XCTAssertEqual(entry.units, 3.0)
        XCTAssertNil(manager.state.bolusReportLedger.entry(bolusId: 33, pumpSerial: Self.pumpSerial), "no up-front part")

        report(start)
        XCTAssertEqual(events(raw: extendedRaw(33)).count, 1, "held, so a re-read sends nothing of its own")
    }

    func testOnFirmwareWithoutBolusDeliveryRecordsTheRunningPartTakesItsDurationFromTheRequest() throws {
        let start = extendedBolusStart(
            bolusId: 44, upFront: 0.75, extended: 0.75, minutes: 60, bolusDeliveryRecords: false, firstSequenceNum: 1200, secondsAgo: 600
        )

        report(start)

        let dose = try XCTUnwrap(events(raw: extendedRaw(44)).first?.dose)
        XCTAssertTrue(dose.isMutable)
        XCTAssertEqual(dose.endDate, try pumpDate(XCTUnwrap(start.last)).addingTimeInterval(.minutes(60)))
    }

    func testAHeldExtendedPartRidesEveryReplacingBatchUntilItsCompletionFinalizesItInOne() throws {
        let start = extendedBolusStart(bolusId: 34, upFront: nil, extended: 2.0, minutes: 120, firstSequenceNum: 500, secondsAgo: 1800)
        report(start)
        let held = try XCTUnwrap(events(raw: extendedRaw(34)).first)

        reportPendingDoses()
        runTempBasal()
        manager.emitPumpEvents(manager.getActivePumpEvents())
        manager.waitForDelegateCalls()

        let replacing = delegate.pumpEventBatches.filter(\.replacePendingEvents)
        XCTAssertEqual(replacing.count, 2)
        for batch in replacing {
            let carried = try XCTUnwrap(batch.events.first { $0.raw == held.raw }, "every replacing batch carries it")
            XCTAssertEqual(carried.dose?.isMutable, true)
            XCTAssertEqual(carried.date, held.date)
            XCTAssertEqual(carried.dose?.startDate, held.dose?.startDate)
            XCTAssertEqual(carried.dose?.endDate, held.dose?.endDate)
            XCTAssertEqual(carried.dose?.programmedUnits, 2.0)
        }

        let stop = bolexCompletion(bolusId: 34, delivered: 0.6, requested: 2.0, stoppedEarly: true, sequenceNum: 503, secondsAgo: 60)
        report(start + [stop])

        let finalizing = try XCTUnwrap(delegate.pumpEventBatches.last)
        XCTAssertTrue(finalizing.replacePendingEvents, "Loop keeps a mutable row over a non-replacing report of its raw (#452)")
        let finalized = try XCTUnwrap(finalizing.events.first { $0.raw == held.raw })
        XCTAssertEqual(finalized.dose?.isMutable, false)
        XCTAssertEqual(finalized.dose?.deliveredUnits, 0.6)
        XCTAssertEqual(finalized.date, held.date)
        XCTAssertTrue(manager.state.bolusReportLedger.heldExtendedParts.isEmpty)

        reportPendingDoses()
        XCTAssertFalse(try XCTUnwrap(delegate.pumpEventBatches.last).events.contains { $0.raw == held.raw }, "not carried once finalized")
    }

    func testLoopAndTrioCountAnExtendedPartWhileItRunsAndKeepItOnceFinalized() throws {
        manager.state.lastReconciliation = now
        // A batch with no dose that outlasts reconciliation never reaches InsulinDeliveryStore.
        runTempBasal()
        let start = extendedBolusStart(bolusId: 35, upFront: 0.5, extended: 2.0, minutes: 60, firstSequenceNum: 600, secondsAgo: 1800)
        report(start)
        reportPendingDoses()

        let running = feedLoop()
        let mutable = try XCTUnwrap(running.normalizedDoses().first { $0.syncIdentifier == extendedRaw(35).hexadecimalString })
        XCTAssertTrue(mutable.isMutable)
        XCTAssertEqual(mutable.programmedUnits, 2.0)
        XCTAssertGreaterThan(feedTrio().boluses.count, 1, "Trio holds both parts")

        let completion = bolexCompletion(bolusId: 35, delivered: 2.0, requested: 2.0, sequenceNum: 605, secondsAgo: 5)
        report(start + [completion])
        manager.startScheduledBasalDose()
        manager.waitForDelegateCalls()

        let loop = feedLoop()
        loop.assertNoDuplicates()
        let stored = try XCTUnwrap(loop.assertPermanent(raw: extendedRaw(35)))
        XCTAssertEqual(stored.dose.deliveredUnits, 2.0)
        XCTAssertNotNil(loop.assertPermanent(raw: HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: 35)))

        let trio = feedTrio()
        trio.assertNoDuplicates()
        let row = try XCTUnwrap(trio.event(syncIdentifier: extendedRaw(35).hexadecimalString))
        XCTAssertFalse(row.isMutable)
        XCTAssertEqual(row.bolusAmount, 2.0)
        XCTAssertEqual(row.isSMB, false)
    }

    func testAHeldExtendedPartWhoseCompletionIsNeverReadIsFinalizedAtItsProgrammedAmount() throws {
        let start = extendedBolusStart(bolusId: 36, upFront: nil, extended: 2.0, minutes: 30, firstSequenceNum: 700, secondsAgo: 60)
        report(start)
        let programmedEnd = pumpDate(start[2]).addingTimeInterval(.minutes(30))

        clock.set(programmedEnd.addingTimeInterval(TandemPumpManager.extendedPartFinalizationWindow - 60))
        reportPendingDoses()
        XCTAssertEqual(delegate.pumpEventBatches.last?.events.first { $0.raw == extendedRaw(36) }?.dose?.isMutable, true, "held while history may still show its end")

        clock.set(programmedEnd.addingTimeInterval(TandemPumpManager.extendedPartFinalizationWindow + 60))
        reportPendingDoses()

        let batch = try XCTUnwrap(delegate.pumpEventBatches.last)
        XCTAssertTrue(batch.replacePendingEvents)
        let dose = try XCTUnwrap(batch.events.first { $0.raw == extendedRaw(36) }?.dose)
        XCTAssertFalse(dose.isMutable)
        XCTAssertEqual(dose.deliveredUnits, 2.0)
        XCTAssertEqual(dose.endDate, programmedEnd)
        XCTAssertTrue(manager.state.bolusReportLedger.heldExtendedParts.isEmpty)

        let lateCompletion = bolexCompletion(bolusId: 36, delivered: 2.0, requested: 2.0, sequenceNum: 703, secondsAgo: 0)
        let batches = delegate.pumpEventBatches.count
        report(start + [lateCompletion])
        XCTAssertEqual(delegate.pumpEventBatches.count, batches, "the host never revises a finalized row")
    }

    func testDeletingThePumpManagerSplitsAHeldExtendedPartAtTheDeletion() throws {
        manager.state.lastReconciliation = now
        // A batch with no dose that outlasts reconciliation never reaches InsulinDeliveryStore.
        runTempBasal()
        let start = extendedBolusStart(bolusId: 37, upFront: nil, extended: 4.0, minutes: 240, firstSequenceNum: 800, secondsAgo: 3600)
        report(start)
        reportPendingDoses()
        let programmedEnd = pumpDate(start[2]).addingTimeInterval(.minutes(240))

        manager.finalizeHeldDosesForDeactivation()
        manager.waitForDelegateCalls()

        let batch = try XCTUnwrap(delegate.pumpEventBatches.last)
        XCTAssertTrue(batch.replacePendingEvents)
        let ranSoFar = try XCTUnwrap(batch.events.first { $0.raw == extendedRaw(37) }?.dose)
        XCTAssertFalse(ranSoFar.isMutable)
        XCTAssertEqual(ranSoFar.endDate, now, "finalized at the deletion, so Loop stores it at once")
        XCTAssertEqual(ranSoFar.deliveredUnits ?? -1, 4.0 * 3586 / 14400, accuracy: 0.0005)
        let remainderEvent = try XCTUnwrap(batch.events.first { $0.dose?.type == .bolus && $0.raw != extendedRaw(37) && $0.dose?.startDate == now })
        let remainder = try XCTUnwrap(remainderEvent.dose)
        XCTAssertFalse(remainder.isMutable)
        XCTAssertEqual(remainder.endDate, programmedEnd, "the pump runs it on after the app forgets it")
        XCTAssertEqual((ranSoFar.deliveredUnits ?? 0) + (remainder.deliveredUnits ?? 0), 4.0, accuracy: 0.0005)

        let loop = feedLoop()
        XCTAssertTrue(loop.mutableDoses.isEmpty, "\(loop.mutableDoses.map(LoopDoseStoreOracle.describe))")
        XCTAssertNotNil(loop.assertPermanent(raw: extendedRaw(37)))
        XCTAssertEqual(loop.normalizedDoses().filter { $0.syncIdentifier == remainderEvent.raw.hexadecimalString }.count, 1, "counted from its pump event")
        let later = programmedEnd.addingTimeInterval(.minutes(1))
        let nextManagersReport = NewPumpEvent.basal(
            dose: UnfinalizedDose(basalRate: 1.0, insulinType: nil, startDate: later).toDoseEntry(),
            date: later
        )
        loop.addPumpEvents([nextManagersReport], lastReconciliation: later, replacePendingEvents: true, now: later)
        XCTAssertNotNil(loop.assertPermanent(raw: remainderEvent.raw), "stored once it has ended")
    }

    func testAHeldExtendedPartIsStillCarriedAfterARelaunchAndNotReportedAgain() throws {
        let start = extendedBolusStart(bolusId: 38, upFront: nil, extended: 2.0, minutes: 120, firstSequenceNum: 900, secondsAgo: 600)
        report(start)

        manager = makeManager(state: TandemPumpManagerState(rawValue: manager.state.rawValue))
        report(start)
        XCTAssertTrue(delegate.pumpEventBatches.isEmpty)

        reportPendingDoses()
        let carried = try XCTUnwrap(delegate.pumpEventBatches.last?.events.first { $0.raw == extendedRaw(38) })
        XCTAssertEqual(carried.dose?.isMutable, true)
        XCTAssertEqual(carried.dose?.endDate, pumpDate(start[2]).addingTimeInterval(.minutes(120)))
    }

    // MARK: - Floors and the boundary

    func testAnExtendedPartBeforeTheFloorIsNotReported() {
        let start = extendedBolusStart(bolusId: 39, upFront: nil, extended: 2.0, minutes: 30, firstSequenceNum: 1000, secondsAgo: 3600)

        report(start, floor: now.addingTimeInterval(-1800))

        XCTAssertTrue(delegate.pumpEventBatches.isEmpty)
        XCTAssertTrue(manager.state.bolusReportLedger.heldExtendedParts.isEmpty)
    }

    func testAFullyExtendedBolusSeenDeliveringHoldsTheBoundaryOnlyUntilItsPartIsReported() throws {
        manager.state.lastReconciliation = now.addingTimeInterval(-600)
        bluetooth.stub(CurrentBolusStatusRequest.self, with: CurrentBolusStatusResponse(
            statusId: CurrentBolusStatusResponse.CurrentBolusStatus.delivering.rawValue,
            bolusId: 40,
            timestamp: nowPumpTimeSec - 586,
            requestedVolume: 2000,
            bolusSourceId: BolusSource.gui.rawValue,
            bolusTypeBitmask: 2
        ))
        manager.fetchBolusStatus(fromSync: false)
        XCTAssertNotNil(manager.state.bolusReportLedger.boundaryHold(pumpSerial: Self.pumpSerial))
        manager.state.lastReconciliation = now

        report(extendedBolusStart(bolusId: 40, upFront: nil, extended: 2.0, minutes: 120, firstSequenceNum: 1100, secondsAgo: 600))

        XCTAssertEqual(delegate.pumpEventBatches.last?.lastReconciliation, now, "the host counts it from its report")
        manager.fetchBolusStatus(fromSync: false)
        XCTAssertNil(manager.state.bolusReportLedger.boundaryHold(pumpSerial: Self.pumpSerial), "a part the host holds is not held for again")
    }

    func testTheLedgerRoundTripsAnExtendedPart() {
        var ledger = BolusReportLedger(trackingSince: Date(timeIntervalSinceReferenceDate: 1000))
        ledger.record(BolusReportLedger.Entry(
            bolusId: 41,
            pumpSerial: Self.pumpSerial,
            origin: .history,
            raw: HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: 41),
            eventDate: Date(timeIntervalSinceReferenceDate: 2000),
            automatic: false,
            isFinalized: true,
            units: 1.0
        ))
        ledger.record(BolusReportLedger.Entry(
            bolusId: 41,
            pumpSerial: Self.pumpSerial,
            origin: .history,
            part: .extended,
            raw: extendedRaw(41),
            eventDate: Date(timeIntervalSinceReferenceDate: 2031),
            automatic: false,
            isFinalized: false,
            units: 2.0,
            programmedEndDate: Date(timeIntervalSinceReferenceDate: 9231)
        ))

        XCTAssertEqual(ledger.entries.count, 2, "the two parts of one bolus are two entries")
        XCTAssertEqual(BolusReportLedger(rawValue: ledger.rawValue), ledger)
    }

    func testAnEntrySavedBeforePartsExistedReadsAsTheStandardPart() throws {
        let entry = BolusReportLedger.Entry(
            bolusId: 42,
            pumpSerial: Self.pumpSerial,
            origin: .history,
            raw: Data([1]),
            eventDate: Date(timeIntervalSinceReferenceDate: 2000),
            automatic: false,
            isFinalized: true
        )
        var raw = entry.rawValue
        raw["part"] = nil

        XCTAssertEqual(BolusReportLedger.Entry(rawValue: raw)?.part, .standard)
    }
}
