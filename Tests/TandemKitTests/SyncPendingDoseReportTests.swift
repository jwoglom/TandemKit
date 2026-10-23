import LoopKit
@testable import TandemKit
import XCTest

/// A sync that read the pump re-sends every dose the host holds as mutable, as the complete
/// pending set, until the dose finalizes (#330, #450).
@available(macOS 13.0, iOS 14.0, *) final class SyncPendingDoseReportTests: XCTestCase {
    private static let pumpSerial: UInt32 = 123_456
    private static let scheduledRate = 1.0
    private static let bolusId = 4100
    private static let bolusUnits = 2.0

    private var bluetooth: StubPumpBluetooth!
    private var clock: ManualClock!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        clock = ManualClock(Date(timeIntervalSinceReferenceDate: 800_000_000))
        manager = makeManager(state: initialState())
        bluetooth.stubBasalPump(profileMilliunits: UInt32(Self.scheduledRate * 1000), tempRateId: 41)
    }

    override func tearDown() {
        manager = nil
        delegate = nil
        delegateQueue = nil
        clock = nil
        bluetooth = nil
        super.tearDown()
    }

    /// History backfill off unless a test turns it on, so a sync runs no tick alongside it.
    private func initialState() -> TandemPumpManagerState {
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.historyBackfill] = false
        state.pumpState.pumpSerial = Self.pumpSerial
        state.insulinType = .novolog
        state.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: Self.scheduledRate)])!
        state.basalDose = UnfinalizedDose(basalRate: Self.scheduledRate, insulinType: .novolog, startDate: clock.now)
        state.hasSyncedBasalRateSchedule = true
        return state
    }

    private func makeManager(state: TandemPumpManagerState) -> TandemPumpManager {
        let manager = TandemPumpManager(state: state, bluetooth: bluetooth, clock: clock)
        delegate = MockPumpManagerDelegate()
        delegate.journalClock = clock
        delegateQueue = DispatchQueue(label: "sync-pending-dose-report-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}
        return manager
    }

    // MARK: - Driving the pump

    private var batches: [MockPumpManagerDelegate.PumpEventBatch] {
        delegateQueue.sync {}
        return delegate.pumpEventBatches
    }

    private func batches(since index: Int) -> [MockPumpManagerDelegate.PumpEventBatch] {
        Array(batches.dropFirst(index))
    }

    private func sync() {
        let synced = expectation(description: "syncPumpData")
        manager.syncPumpData { _ in synced.fulfill() }
        wait(for: [synced], timeout: 5)
        delegateQueue.sync {}
    }

    /// Returns the `raw` the bolus was first reported under.
    private func startBolus() throws -> Data {
        bluetooth.stub(BolusPermissionRequest.self, with: BolusPermissionResponse(status: 0, bolusId: Self.bolusId, nackReasonId: 0))
        bluetooth.stub(InitiateBolusRequest.self, with: InitiateBolusResponse(status: 0, bolusId: Self.bolusId, statusTypeId: 0))
        let before = batches.count
        let done = expectation(description: "enactBolus")
        manager.enactBolus(units: Self.bolusUnits, activationType: .manualNoRecommendation) { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        let reported = batches(since: before).flatMap(\.events).filter { $0.dose?.type == .bolus }
        XCTAssertEqual(reported.map(\.dose?.isMutable), [true])
        return try XCTUnwrap(reported.first?.raw)
    }

    /// Returns the `raw` the temp basal was first reported under.
    private func startTempBasal(unitsPerHour: Double = 1.5) throws -> Data {
        let before = batches.count
        let done = expectation(description: "enactTempBasal")
        manager.enactTempBasal(unitsPerHour: unitsPerHour, for: .minutes(30)) { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        let reported = batches(since: before).flatMap(\.events).filter { $0.dose?.type == .tempBasal }
        XCTAssertEqual(reported.map(\.dose?.isMutable), [true])
        return try XCTUnwrap(reported.first?.raw)
    }

    private func stubNoBolusRunning() {
        bluetooth.stub(CurrentBolusStatusRequest.self, with: CurrentBolusStatusResponse(
            statusId: 0,
            bolusId: 0,
            timestamp: 0,
            requestedVolume: 0,
            bolusSourceId: 0,
            bolusTypeBitmask: 0
        ))
    }

    /// bolusId 0 with no delivery in progress is how the pump says the bolus is over.
    private func finishBolus(deliveredMilliunits: UInt32?) {
        bluetooth.stub(CurrentBolusStatusRequest.self, with: CurrentBolusStatusResponse(
            statusId: 0,
            bolusId: 0,
            timestamp: 0,
            requestedVolume: UInt32(Self.bolusUnits * 1000),
            bolusSourceId: 0,
            bolusTypeBitmask: 0
        ))
        bluetooth.stub(LastBolusStatusRequest.self) { _ in
            deliveredMilliunits.map { volume in
                LastBolusStatusResponse(
                    status: 0,
                    bolusId: Self.bolusId,
                    timestamp: 0,
                    deliveredVolume: volume,
                    bolusStatusId: 0,
                    bolusSourceId: 0,
                    bolusTypeBitmask: 0,
                    extendedBolusDuration: 0
                )
            }
        }
        manager.fetchBolusStatus(fromSync: false)
        delegateQueue.sync {}
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

    // MARK: - Re-sent

    func testASyncWhileABolusRunsReSendsItAsTheCompletePendingSet() throws {
        let raw = try startBolus()
        clock.advance(by: 5)

        let before = batches.count
        sync()

        let batch = try XCTUnwrap(batches(since: before).last)
        XCTAssertTrue(batch.replacePendingEvents)
        XCTAssertEqual(batch.events.map(\.raw), [raw])
        let dose = try XCTUnwrap(batch.events.first?.dose)
        XCTAssertTrue(dose.isMutable)
        XCTAssertEqual(dose.programmedUnits, Self.bolusUnits)
        XCTAssertNil(dose.deliveredUnits)
    }

    func testASyncWhileATempBasalRunsReSendsItUnderItsRawToItsScheduledEnd() throws {
        let start = clock.now
        let raw = try startTempBasal(unitsPerHour: 1.5)
        clock.advance(by: .minutes(5))
        stubNoBolusRunning()

        let before = batches.count
        sync()

        let batch = try XCTUnwrap(batches(since: before).last)
        XCTAssertTrue(batch.replacePendingEvents)
        XCTAssertEqual(batch.events.map(\.raw), [raw])
        let dose = try XCTUnwrap(batch.events.first?.dose)
        XCTAssertTrue(dose.isMutable)
        XCTAssertEqual(dose.unitsPerHour, 1.5, accuracy: 0.001)
        XCTAssertEqual(dose.startDate, start)
        XCTAssertEqual(dose.endDate, start.addingTimeInterval(.minutes(30)))
    }

    func testASyncWhileATempBasalAndABolusRunReSendsBoth() throws {
        let tempRaw = try startTempBasal()
        let bolusRaw = try startBolus()
        clock.advance(by: 5)

        let before = batches.count
        sync()

        let batch = try XCTUnwrap(batches(since: before).last)
        XCTAssertTrue(batch.replacePendingEvents)
        XCTAssertEqual(Set(batch.events.map(\.raw)), [tempRaw, bolusRaw])
        XCTAssertTrue(batch.events.allSatisfy { $0.dose?.isMutable == true })
    }

    func testASyncAfterARelaunchMidBolusReSendsTheRestoredBolus() throws {
        let raw = try startBolus()
        manager = makeManager(state: TandemPumpManagerState(rawValue: manager.state.rawValue))
        clock.advance(by: 5)

        sync()

        let batch = try XCTUnwrap(batches.last)
        XCTAssertTrue(batch.replacePendingEvents)
        XCTAssertEqual(batch.events.first { $0.raw == raw }?.dose?.isMutable, true)
    }

    func testASyncReSendsABolusHeldForItsDeliveredVolume() throws {
        let raw = try startBolus()
        finishBolus(deliveredMilliunits: nil)
        XCTAssertNotNil(manager.state.pendingBolusFinalization)
        clock.advance(by: 5)

        let before = batches.count
        sync()

        XCTAssertNotNil(manager.state.pendingBolusFinalization, "the pump still has no delivered volume for it")
        let batch = try XCTUnwrap(batches(since: before).last)
        XCTAssertTrue(batch.replacePendingEvents)
        XCTAssertEqual(batch.events.map(\.raw), [raw])
        XCTAssertEqual(batch.events.first?.dose?.isMutable, true)
    }

    func testABolusReSentOnEverySyncStaysOneDoseInBothHostsUntilItFinalizes() throws {
        let raw = try startBolus()

        for round in 1 ... 4 {
            clock.advance(by: 5)
            sync()

            let loop = feedLoop()
            let stored = try XCTUnwrap(loop.assertSingleDose(raw: raw, "round \(round)"))
            XCTAssertTrue(stored.isMutable, "round \(round)")
            XCTAssertTrue(loop.deletedDoses.isEmpty, "round \(round): \(loop.deletedDoses.map(LoopDoseStoreOracle.describe))")
            let trio = feedTrio()
            XCTAssertEqual(trio.boluses.count, 1, "round \(round): \(trio.boluses)")
            XCTAssertTrue(trio.purged.isEmpty, "round \(round): \(trio.purged)")
        }

        finishBolus(deliveredMilliunits: 1500)

        let stored = try XCTUnwrap(feedLoop().assertPermanent(raw: raw))
        XCTAssertEqual(stored.dose.deliveredUnits, 1.5)
        let trio = feedTrio()
        XCTAssertEqual(trio.boluses.map(\.isMutable), [false])
        XCTAssertEqual(trio.boluses.first?.bolusAmount, 1.5)
    }

    func testATempBasalThatRunsOutWhileABolusRunsIsFinalizedInBatchesThatKeepTheBolus() throws {
        let tempRaw = try startTempBasal()
        clock.advance(by: .minutes(30) - 20)
        let bolusRaw = try startBolus()
        clock.advance(by: 40)
        bluetooth.stub(CurrentBasalStatusRequest.self, with: CurrentBasalStatusResponse(
            profileBasalRate: 1000,
            currentBasalRate: 1000,
            basalModifiedBitmask: 0
        ))

        let before = batches.count
        sync()

        let replacing = batches(since: before).filter(\.replacePendingEvents)
        XCTAssertTrue(replacing.contains { $0.events.contains { $0.raw == tempRaw && $0.dose?.isMutable == false } }, "\(replacing)")
        XCTAssertTrue(replacing.allSatisfy { $0.events.contains { $0.raw == bolusRaw && $0.dose?.isMutable == true } }, "\(replacing)")
        let loop = feedLoop()
        XCTAssertNotNil(loop.assertPermanent(raw: tempRaw))
        XCTAssertEqual(loop.dose(raw: bolusRaw)?.isMutable, true)
    }

    // MARK: - Boundary only

    private func cancelTempBasal() {
        let done = expectation(description: "cancel")
        manager.enactTempBasal(unitsPerHour: 0, for: 0) { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        delegateQueue.sync {}
    }

    /// The records the pump writes for a quick bolus of `units`, activated at `activation` and
    /// finished at `completion`.
    private func quickBolusRecords(bolusId: Int, units: Float, activation: Date, completion: Date, firstSequenceNum: UInt32) -> [HistoryLog] {
        let activated = UInt32(Dates.fromInstantToJan12008EpochSeconds(activation))
        return [
            BolusActivatedHistoryLog(pumpTimeSec: activated, sequenceNum: firstSequenceNum, bolusId: bolusId, selectedIob: 0, iob: 0, bolusSize: units),
            BolusDeliveryHistoryLog(
                pumpTimeSec: activated,
                sequenceNum: firstSequenceNum + 1,
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
            ),
            BolusCompletedHistoryLog(
                pumpTimeSec: UInt32(Dates.fromInstantToJan12008EpochSeconds(completion)),
                sequenceNum: firstSequenceNum + 2,
                completionStatusId: 3,
                bolusId: bolusId,
                iob: units,
                insulinDelivered: units,
                insulinRequested: units
            )
        ]
    }

    /// Loop saves a batch's doses only under a boundary past its newest finalized basal, and counts a
    /// finalized dose dated before the boundary only once saved (#353). A cancel leaves the boundary
    /// at that end, so a pump bolus history reports before the next sync waits for the sync's batch.
    func testASyncWithNothingRunningCarriesAHistoryBolusLoopHasNotStored() throws {
        manager.state.featureFlags[.historyBackfill] = true
        manager.state.featureFlags[.historyDoseReporting] = true
        manager.state.bolusReportLedger = BolusReportLedger(trackingSince: .distantPast)
        manager.state.quickBolusEnabled = false
        stubNoBolusRunning()
        _ = try startTempBasal()
        clock.advance(by: .minutes(10))
        cancelTempBasal()
        let cancelledAt = clock.now
        XCTAssertEqual(manager.state.lastReconciliation, cancelledAt)

        let records = quickBolusRecords(
            bolusId: 77,
            units: 1.0,
            activation: cancelledAt.addingTimeInterval(-.minutes(4)),
            completion: cancelledAt.addingTimeInterval(-.minutes(3)),
            firstSequenceNum: 500
        )
        manager.storeHistoryLogs(records, now: clock.now)
        manager.reportHistoryBoluses(in: 500 ... 502, pumpSerial: try XCTUnwrap(HistoryLogSyncIdentifier.PumpSerial(Self.pumpSerial)), floor: .distantPast, now: clock.now)
        let reported = try XCTUnwrap(batches.last)
        let bolusRaw = try XCTUnwrap(reported.events.first { $0.dose?.type == .bolus }?.raw)
        XCTAssertEqual(reported.lastReconciliation, cancelledAt)
        XCTAssertNil(feedLoop().dose(raw: bolusRaw), "Loop saves nothing under a boundary at its newest finalized basal's end")

        clock.advance(by: .minutes(5))
        let before = batches.count
        sync()

        let batch = try XCTUnwrap(batches(since: before).last)
        XCTAssertFalse(batch.replacePendingEvents)
        XCTAssertEqual(batch.events.map(\.raw), [bolusRaw])
        XCTAssertEqual(batch.lastReconciliation, clock.now)
        let loop = feedLoop()
        XCTAssertEqual(try XCTUnwrap(loop.assertPermanent(raw: bolusRaw)).dose.deliveredUnits, 1.0)
        XCTAssertGreaterThan(loop.iob(at: clock.now), 0)
        _ = feedTrio().assertSingleBolus(at: cancelledAt.addingTimeInterval(-.minutes(4)), amount: 1.0)

        clock.advance(by: .minutes(5))
        let again = batches.count
        sync()

        XCTAssertEqual(batches(since: again).last?.events.isEmpty, true, "carried once")
    }

    func testASyncWithNothingRunningSendsOnlyTheBoundary() throws {
        stubNoBolusRunning()
        sync()

        let batch = try XCTUnwrap(batches.last)
        XCTAssertFalse(batch.replacePendingEvents)
        XCTAssertTrue(batch.events.isEmpty)
        XCTAssertEqual(batch.lastReconciliation, manager.state.lastReconciliation)
    }

    func testASyncWhoseBasalReadGoesUnansweredReportsNothing() throws {
        _ = try startBolus()
        let boundary = manager.state.lastReconciliation
        bluetooth.stub(CurrentBasalStatusRequest.self) { _ in nil }
        bluetooth.stub(InsulinStatusRequest.self, with: InsulinStatusResponse(currentInsulinAmount: 150, isEstimate: 0, insulinLowAmount: 20))
        clock.advance(by: 5)

        let before = batches.count
        sync()

        XCTAssertTrue(batches(since: before).isEmpty, "\(batches(since: before))")
        XCTAssertEqual(manager.state.lastReconciliation, boundary)
    }

    /// The sync defers to the bolus it tracks rather than read it, and the host counts it already.
    func testASyncThatDefersToARunningBolusMovesTheBoundary() throws {
        _ = try startBolus()
        clock.advance(by: 5)
        bluetooth.resetRecordedTraffic()

        sync()

        XCTAssertFalse(bluetooth.didSend(CurrentBolusStatusRequest.self))
        XCTAssertEqual(manager.state.lastReconciliation, clock.now)
    }

    func testADeliveryChangeWaitingForHistoryKeepsTheTempTheHostHolds() throws {
        manager.state.featureFlags[.historyBackfill] = true
        let tempRaw = try startTempBasal()
        let bolusRaw = try startBolus()
        clock.advance(by: .minutes(2))
        // The pump ended the temp on its own; the host holds it until history dates the end.
        bluetooth.stub(CurrentBasalStatusRequest.self, with: CurrentBasalStatusResponse(
            profileBasalRate: 1000,
            currentBasalRate: 1000,
            basalModifiedBitmask: 0
        ))
        manager.fetchBasalStatus()
        XCTAssertNotNil(manager.state.deliveryTransitions.pending)

        let before = batches.count
        manager.reportPendingDoses()

        let batch = try XCTUnwrap(batches(since: before).last)
        XCTAssertTrue(batch.replacePendingEvents)
        XCTAssertEqual(Set(batch.events.map(\.raw)), [tempRaw, bolusRaw])
        XCTAssertTrue(batch.events.allSatisfy { $0.dose?.isMutable == true }, "the temp as the host holds it, not the placeholder")
        XCTAssertEqual(feedLoop().dose(raw: tempRaw)?.isMutable, true)

        manager.settleDeliveryTransition()

        let loop = feedLoop()
        XCTAssertNotNil(loop.assertPermanent(raw: tempRaw))
        XCTAssertEqual(loop.dose(raw: bolusRaw)?.isMutable, true)
    }
}
