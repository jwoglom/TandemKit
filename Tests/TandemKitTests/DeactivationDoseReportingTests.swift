import LoopKit
@testable import TandemKit
import XCTest

/// Deleting the pump manager finalizes the doses the host holds as mutable at the ends the pump gives
/// them, since it keeps delivering after the app has forgotten it (#350).
@available(macOS 13.0, iOS 14.0, *) final class DeactivationDoseReportingTests: XCTestCase {
    private static let pumpSerial: UInt32 = 246_810
    private static let referenceDay = Calendar.current.startOfDay(for: Date(timeIntervalSinceReferenceDate: 700_000_000))
    private static let bolusId = 3210
    private static let bolusUnits = 2.0

    private var bluetooth: StubPumpBluetooth!
    private var clock: ManualClock!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!
    /// What the stub pump runs; nil for its profile.
    private var runningPercent: Int?

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        clock = ManualClock(at(.hours(10)))
    }

    override func tearDown() {
        manager = nil
        delegate = nil
        delegateQueue = nil
        clock = nil
        bluetooth = nil
        super.tearDown()
    }

    private func at(_ time: TimeInterval) -> Date {
        Self.referenceDay.addingTimeInterval(time)
    }

    /// 1 U/hr until 14:00 and 2 U/hr after, on the host and the pump alike.
    private func startManager() {
        let schedule = BasalRateSchedule(dailyItems: [
            RepeatingScheduleValue(startTime: 0, value: 1.0),
            RepeatingScheduleValue(startTime: .hours(14), value: 2.0)
        ])!
        var state = TandemPumpManagerState(basalRateSchedule: schedule)
        state.hasSyncedBasalRateSchedule = true
        state.insulinType = .novolog
        state.pumpState.pumpSerial = Self.pumpSerial
        state.basalDose = UnfinalizedDose(basalRate: 1.0, insulinType: .novolog, startDate: clock.now)
        manager = TandemPumpManager(state: state, bluetooth: bluetooth, clock: clock)
        delegate = MockPumpManagerDelegate()
        delegate.journalClock = clock
        delegateQueue = DispatchQueue(label: "deactivation-dose-reporting-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}

        bluetooth.stub(CurrentBasalStatusRequest.self) { [unowned self] _ in
            let profile = UInt32((self.manager.getScheduledBasalRate() * 1000).rounded())
            return CurrentBasalStatusResponse(
                profileBasalRate: profile,
                currentBasalRate: profile * UInt32(self.runningPercent ?? 100) / 100,
                basalModifiedBitmask: self.runningPercent == nil ? 0 : 0x02
            )
        }
        bluetooth.stub(SetTempRateRequest.self) { [unowned self] request in
            self.runningPercent = (request as? SetTempRateRequest)?.percent
            return SetTempRateResponse(status: 0, tempRateId: 41)
        }
        bluetooth.stub(StopTempRateRequest.self) { [unowned self] _ in
            self.runningPercent = nil
            return StopTempRateResponse(status: 0, tempRateId: 41)
        }
        bluetooth.stub(TempRateRequest.self) { [unowned self] _ in
            TempRateResponse(active: self.runningPercent != nil, percentage: self.runningPercent ?? 0, startTimeRaw: 0, duration: 0)
        }
        bluetooth.stub(BolusPermissionRequest.self, with: BolusPermissionResponse(status: 0, bolusId: Self.bolusId, nackReasonId: 0))
        bluetooth.stub(InitiateBolusRequest.self, with: InitiateBolusResponse(status: 0, bolusId: Self.bolusId, statusTypeId: 0))
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
    }

    private func enactTempBasal(unitsPerHour: Double, for duration: TimeInterval = .minutes(30)) -> Data? {
        let done = expectation(description: "temp basal completion")
        manager.enactTempBasal(unitsPerHour: unitsPerHour, for: duration) { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return events.last { $0.dose?.type == .tempBasal }?.raw
    }

    private func enactBolus() -> Data? {
        let done = expectation(description: "enactBolus")
        manager.enactBolus(units: Self.bolusUnits, activationType: .manualNoRecommendation) { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return events.last { $0.dose?.type == .bolus }?.raw
    }

    private func stubCurrentBolus(statusId: Int, bolusId: Int, at timestamp: Date? = nil) {
        bluetooth.stub(CurrentBolusStatusRequest.self, with: CurrentBolusStatusResponse(
            statusId: statusId,
            bolusId: bolusId,
            timestamp: timestamp.map { UInt32(Dates.fromInstantToJan12008EpochSeconds($0)) } ?? 0,
            requestedVolume: UInt32(Self.bolusUnits * 1000),
            bolusSourceId: 0,
            bolusTypeBitmask: 0
        ))
    }

    private func deactivate() {
        let done = expectation(description: "prepareForDeactivation")
        manager.prepareForDeactivation { _ in done.fulfill() }
        wait(for: [done], timeout: 5)
        delegateQueue.sync {}
    }

    private var events: [NewPumpEvent] {
        delegateQueue.sync {}
        return delegate.pumpEventBatches.flatMap(\.events)
    }

    private var batchCount: Int {
        delegateQueue.sync {}
        return delegate.pumpEventBatches.count
    }

    private func batches(since count: Int) -> [MockPumpManagerDelegate.PumpEventBatch] {
        delegateQueue.sync {}
        return Array(delegate.pumpEventBatches.dropFirst(count))
    }

    /// The journal position of the last batch and of `pumpManagerWillDeactivate`.
    private func lastBatchAndDeactivation() -> (batch: Int?, willDeactivate: Int?) {
        let journal = delegate.journal
        let batch = journal.last { $0.pumpEventBatch != nil }?.index
        let willDeactivate = journal.first { if case .willDeactivate = $0.kind { true } else { false } }?.index
        return (batch, willDeactivate)
    }

    // MARK: - Running doses

    func testARunningTempBasalIsCutNowAndItsRemainderReportedOnItsOwnBeforeTheHostHearsOfTheDeactivation() throws {
        startManager()
        let tempRaw = try XCTUnwrap(enactTempBasal(unitsPerHour: 1.5))
        clock.advance(by: .minutes(1))
        let bolusRaw = try XCTUnwrap(enactBolus())
        let deliveryStart = clock.now.addingTimeInterval(15)
        clock.set(deliveryStart.addingTimeInterval(1))
        stubCurrentBolus(statusId: 1, bolusId: Self.bolusId, at: deliveryStart)
        manager.fetchBolusStatus(fromSync: false)
        clock.advance(by: 20)
        let deactivatedAt = clock.now
        let before = batchCount

        deactivate()

        XCTAssertEqual(batches(since: before).count, 1)
        let final = try XCTUnwrap(batches(since: before).last)
        XCTAssertTrue(final.replacePendingEvents, "a complete set of what the host holds as mutable")
        XCTAssertEqual(final.lastReconciliation, deactivatedAt)
        let order = lastBatchAndDeactivation()
        XCTAssertLessThan(try XCTUnwrap(order.batch), try XCTUnwrap(order.willDeactivate))
        XCTAssertEqual(delegate.willDeactivateCount, 1)

        let temps = final.events.filter { $0.dose?.type == .tempBasal }
        XCTAssertEqual(temps.count, 2)
        XCTAssertEqual(temps.first?.raw, tempRaw, "what ran so far, under the identity the host holds")
        XCTAssertNotEqual(temps.last?.raw, tempRaw, "the remainder, which Loop stores only once it has ended")
        let doses = temps.compactMap(\.dose)
        XCTAssertEqual(doses.map(\.isMutable), [false, false])
        XCTAssertEqual(doses.map(\.startDate), [at(.hours(10)), deactivatedAt])
        XCTAssertEqual(doses.map(\.endDate), [deactivatedAt, at(.hours(10) + .minutes(30))], "the pump runs it to its end")
        XCTAssertEqual(doses.map(\.unitsPerHour), [1.5, 1.5])
        XCTAssertEqual(doses.compactMap(\.deliveredUnits).reduce(0, +), 0.75, accuracy: 0.001)
        XCTAssertEqual(doses.map(\.automatic), [true, true])

        let bolus = try XCTUnwrap(final.events.first { $0.raw == bolusRaw }?.dose)
        XCTAssertFalse(bolus.isMutable)
        XCTAssertEqual(bolus.programmedUnits, Self.bolusUnits)
        XCTAssertEqual(bolus.deliveredUnits, Self.bolusUnits, "the pump finishes it")
        XCTAssertEqual(bolus.startDate, deliveryStart)
        XCTAssertEqual(bolus.endDate, deactivatedAt, "Loop stores a finalized dose only once it has ended")

        XCTAssertFalse(final.events.contains { $0.type == .suspend || $0.type == .basal }, "\(final.events)")
        XCTAssertNil(manager.state.bolusDose)
        XCTAssertEqual(manager.state.bolusState, .noBolus)
        XCTAssertEqual(manager.state.basalDose.type, .basal)
        XCTAssertEqual(manager.state.basalDose.startDate, at(.hours(10) + .minutes(30)))
        let ledgerEntry = manager.state.bolusReportLedger.entry(bolusId: Self.bolusId, pumpSerial: Self.pumpSerial)
        XCTAssertEqual(ledgerEntry?.isFinalized, true)
    }

    func testABolusPastItsEstimateEndsThere() throws {
        startManager()
        let bolusRaw = try XCTUnwrap(enactBolus())
        let programmedAt = clock.now
        clock.advance(by: .minutes(5))

        deactivate()

        let bolus = try XCTUnwrap(events.last { $0.raw == bolusRaw }?.dose)
        XCTAssertFalse(bolus.isMutable)
        XCTAssertEqual(bolus.deliveredUnits, Self.bolusUnits)
        XCTAssertEqual(
            bolus.endDate,
            programmedAt.addingTimeInterval(TandemPumpCapabilities.bolusInitiationDelay + manager.estimatedDuration(toBolus: Self.bolusUnits))
        )
    }

    func testATempBasalIsCutWhereThePumpRescalesItAtASegmentChange() throws {
        clock.set(at(.hours(13) + .minutes(45)))
        startManager()
        let tempRaw = try XCTUnwrap(enactTempBasal(unitsPerHour: 1.5))
        clock.advance(by: .minutes(5))
        let before = batchCount

        deactivate()

        let temps = try XCTUnwrap(batches(since: before).last).events.filter { $0.dose?.type == .tempBasal }
        XCTAssertEqual(temps.first?.raw, tempRaw)
        let doses = temps.compactMap(\.dose)
        XCTAssertEqual(doses.map(\.isMutable), [false, false, false])
        XCTAssertEqual(doses.map(\.startDate), [at(.hours(13) + .minutes(45)), at(.hours(13) + .minutes(50)), at(.hours(14))])
        XCTAssertEqual(doses.map(\.endDate), [at(.hours(13) + .minutes(50)), at(.hours(14)), at(.hours(14) + .minutes(15))])
        XCTAssertEqual(doses.map(\.unitsPerHour), [1.5, 1.5, 3.0])
        XCTAssertEqual(doses.compactMap(\.deliveredUnits), [0.125, 0.25, 0.75])
        XCTAssertEqual(manager.state.basalDose.value, 2.0)
        let serial = try XCTUnwrap(HistoryLogSyncIdentifier.PumpSerial(Self.pumpSerial))
        XCTAssertEqual(temps.last?.raw, HistoryLogSyncIdentifier.tempRatePart(pumpSerial: serial, tempRateId: 41, part: 1), "as a later pump manager counts the temp's parts from history")
        XCTAssertFalse([tempRaw, temps.last?.raw].contains(temps[1].raw))
    }

    func testATempBasalStartedThisSecondIsCutASecondOn() throws {
        startManager()
        let tempRaw = try XCTUnwrap(enactTempBasal(unitsPerHour: 1.5))

        deactivate()

        let temps = events.filter { $0.dose?.type == .tempBasal && $0.dose?.isMutable == false }
        XCTAssertEqual(temps.count, 2)
        XCTAssertEqual(temps.first?.raw, tempRaw)
        XCTAssertEqual(temps.map(\.date), [at(.hours(10)), at(.hours(10) + 1)])
    }

    // MARK: - Doses already over on the pump

    func testABolusWhoseVolumeIsUnconfirmedIsFinalizedFromItsHistoryRecord() throws {
        startManager()
        let bolusRaw = try XCTUnwrap(enactBolus())
        let programmedAt = clock.now
        clock.advance(by: manager.estimatedDuration(toBolus: Self.bolusUnits) + .minutes(2))
        stubCurrentBolus(statusId: 0, bolusId: 0)
        manager.fetchBolusStatus(fromSync: false)
        XCTAssertNotNil(manager.state.pendingBolusFinalization)
        let pumpEnd = programmedAt.addingTimeInterval(60)
        manager.storeHistoryLogs([BolusCompletedHistoryLog(
            pumpTimeSec: UInt32(Dates.fromInstantToJan12008EpochSeconds(pumpEnd)),
            sequenceNum: 900,
            completionStatusId: 3,
            bolusId: Self.bolusId,
            iob: 0,
            insulinDelivered: 1.234,
            insulinRequested: Float(Self.bolusUnits)
        )])

        deactivate()

        let bolus = try XCTUnwrap(events.last { $0.raw == bolusRaw }?.dose)
        XCTAssertFalse(bolus.isMutable)
        XCTAssertEqual(bolus.deliveredUnits, 1.234)
        XCTAssertEqual(bolus.endDate.timeIntervalSince(pumpEnd), 0, accuracy: 1, "dated by the record")
        XCTAssertNil(manager.state.pendingBolusFinalization)
    }

    func testABolusWhoseVolumeIsUnconfirmedIsFinalizedWithTheAmountItWasHeldWith() throws {
        startManager()
        let bolusRaw = try XCTUnwrap(enactBolus())
        clock.advance(by: 30)
        bluetooth.stub(CancelBolusRequest.self, with: CancelBolusResponse(statusId: 0, bolusId: Self.bolusId, reasonId: 0))
        let cancelled = expectation(description: "cancelBolus")
        manager.cancelBolus { _ in cancelled.fulfill() }
        // The cancel path waits ~2s for the pump to store the bolus before reading it back.
        wait(for: [cancelled], timeout: 15)
        let fallback = try XCTUnwrap(manager.state.pendingBolusFinalization?.deliveredUnits)
        XCTAssertLessThan(fallback, Self.bolusUnits)

        deactivate()

        let bolus = try XCTUnwrap(events.last { $0.raw == bolusRaw }?.dose)
        XCTAssertFalse(bolus.isMutable)
        XCTAssertEqual(bolus.deliveredUnits, fallback, "the time delivery ran, not the programmed amount")
    }

    func testATempBasalThePumpEndedBeforeHistoryDatedItEndsAtTheReading() throws {
        startManager()
        let tempRaw = try XCTUnwrap(enactTempBasal(unitsPerHour: 1.5))
        clock.advance(by: .minutes(5))
        runningPercent = nil
        manager.fetchBasalStatus()
        XCTAssertNotNil(manager.state.deliveryTransitions.pending, "left for history to date")
        clock.advance(by: .minutes(1))

        deactivate()

        let temp = try XCTUnwrap(events.last { $0.raw == tempRaw }?.dose)
        XCTAssertFalse(temp.isMutable)
        XCTAssertEqual(temp.endDate, at(.hours(10) + .minutes(5)), "above the schedule, ended at detection")
        let order = lastBatchAndDeactivation()
        XCTAssertLessThan(try XCTUnwrap(order.batch), try XCTUnwrap(order.willDeactivate))
        XCTAssertNil(manager.state.deliveryTransitions.pending)
    }

    // MARK: - Nothing held

    func testWithNothingHeldTheHostIsOnlyToldOfTheDeactivation() {
        startManager()

        deactivate()

        XCTAssertTrue(delegate.pumpEventBatches.isEmpty, "\(delegate.pumpEventBatches)")
        XCTAssertEqual(delegate.willDeactivateCount, 1)
    }

    // MARK: - What the hosts keep

    /// Loop deletes a mutable dose at the next replacing batch that leaves it out, from any pump
    /// manager, and stores a finalized one only once it has ended.
    func testLoopAndTrioKeepEveryPartOnceAndLoopStoresTheRemainderWhenItEnds() throws {
        startManager()
        let tempRaw = try XCTUnwrap(enactTempBasal(unitsPerHour: 1.5))
        clock.advance(by: .minutes(1))
        let bolusRaw = try XCTUnwrap(enactBolus())
        clock.advance(by: 20)
        let before = batchCount

        deactivate()

        let remainderRaw = try XCTUnwrap(batches(since: before).last?.events.last { $0.dose?.type == .tempBasal }?.raw)
        let loop = LoopDoseStoreOracle()
        let trio = TrioDoseStoreOracle()
        delegate.feed(loop)
        delegate.feed(trio)
        XCTAssertNotNil(loop.assertPermanent(raw: tempRaw))
        XCTAssertNotNil(loop.assertPermanent(raw: bolusRaw))
        XCTAssertNil(loop.dose(raw: remainderRaw), "not stored before it ends")
        XCTAssertEqual(loop.pumpEventRow(raw: remainderRaw)?.mutable, false)
        let counted = loop.normalizedDoses().filter { $0.type == .tempBasal }.sorted { $0.startDate < $1.startDate }
        XCTAssertEqual(counted.map(\.syncIdentifier), [tempRaw.hexadecimalString, remainderRaw.hexadecimalString], "counted once each")
        XCTAssertEqual(counted.first?.endDate, counted.last?.startDate)
        XCTAssertEqual(counted.last?.endDate, at(.hours(10) + .minutes(30)))

        let next = at(.hours(10) + .minutes(40))
        let nextBatch = [NewPumpEvent.basal(dose: UnfinalizedDose(basalRate: 1.0, insulinType: .novolog, startDate: next).toDoseEntry(), date: next)]
        loop.addPumpEvents(nextBatch, lastReconciliation: next, replacePendingEvents: true, now: next)
        trio.addPumpEvents(nextBatch, lastReconciliation: next, replacePendingEvents: true, now: next)

        let remainder = try XCTUnwrap(loop.assertPermanent(raw: remainderRaw))
        XCTAssertEqual(remainder.dose.endDate, at(.hours(10) + .minutes(30)))
        XCTAssertNotNil(loop.assertPermanent(raw: tempRaw))
        XCTAssertEqual(try XCTUnwrap(loop.assertPermanent(raw: bolusRaw)).dose.deliveredUnits, Self.bolusUnits)
        XCTAssertEqual(trio.tempBasals.map(\.isMutable), [false, false])
        XCTAssertEqual(trio.tempBasals.compactMap(\.tempBasalDurationMinutes).reduce(0, +), 30)
        XCTAssertEqual(trio.boluses.map(\.isMutable), [false])
        XCTAssertEqual(trio.boluses.first?.bolusAmount, Decimal(Self.bolusUnits))
        trio.assertNoDuplicates()
    }
}
