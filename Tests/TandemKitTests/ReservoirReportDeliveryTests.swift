import LoopKit
@testable import TandemKit
import XCTest

/// The driver reads the reservoir before the host adopts it — pairing ends in a full
/// `syncPumpData` — and `didReadReservoirValue` is one-shot, so a dropped call leaves the host on
/// a stale cartridge level.
@available(macOS 13.0, iOS 14.0, *) final class ReservoirReportDeliveryTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    /// Shared by every attach, since a host keeps one queue for the manager's life.
    private var delegateQueue: DispatchQueue!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        delegateQueue = DispatchQueue(label: "reservoir-report-test")
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
    }

    override func tearDown() {
        manager = nil
        bluetooth = nil
        delegateQueue = nil
        super.tearDown()
    }

    private func stubReservoir(units: Int) {
        bluetooth.stub(InsulinStatusRequest.self, with: InsulinStatusResponse(
            currentInsulinAmount: units,
            isEstimate: 0,
            insulinLowAmount: 20
        ))
        bluetooth.stubIdleDelivery()
    }

    /// The reading reaches the host only once a sync's delivery reads move the boundary past it.
    private func sync() {
        let synced = expectation(description: "syncPumpData completes")
        manager.syncPumpData { _ in synced.fulfill() }
        wait(for: [synced], timeout: 5.0)
    }

    /// Drains the queue on the way out so assertions see everything the attach kicked off.
    @discardableResult
    private func attachDelegate(
        _ delegate: MockPumpManagerDelegate,
        queueFirst: Bool = false
    ) -> DispatchQueue {
        let queue: DispatchQueue = delegateQueue

        if queueFirst {
            manager.delegateQueue = queue
            manager.pumpManagerDelegate = delegate
        } else {
            // Trio's order.
            manager.pumpManagerDelegate = delegate
            manager.delegateQueue = queue
        }

        queue.sync {}
        return queue
    }

    func testASyncsReadingIsReportedWhenADelegateIsAttached() {
        let delegate = MockPumpManagerDelegate()
        let queue = attachDelegate(delegate)

        let readReservoir = expectation(description: "delegate received reservoir value")
        delegate.didReadReservoirExpectation = readReservoir
        stubReservoir(units: 150)

        sync()
        wait(for: [readReservoir], timeout: 2.0)
        queue.sync {}

        XCTAssertEqual(delegate.reservoirReadings.map(\.units), [150])
        XCTAssertFalse(
            manager.state.lastReservoirReadingNeedsReport,
            "A delivered reading must not stay queued"
        )
    }

    func testReadingTakenWithoutADelegateIsReportedWhenOneAttaches() {
        stubReservoir(units: 50)

        sync()

        XCTAssertEqual(manager.reservoirLevel?.unitVolume, 50)
        XCTAssertTrue(
            manager.state.lastReservoirReadingNeedsReport,
            "A reading with nowhere to go must be held, not dropped"
        )

        let delegate = MockPumpManagerDelegate()
        let readReservoir = expectation(description: "delegate received the held reservoir value")
        delegate.didReadReservoirExpectation = readReservoir

        let queue = attachDelegate(delegate)
        wait(for: [readReservoir], timeout: 2.0)
        queue.sync {}

        XCTAssertEqual(delegate.reservoirReadings.map(\.units), [50])
        XCTAssertEqual(
            delegate.reservoirReadings.last?.date,
            manager.reservoirLevel?.startDate,
            "The held reading keeps the time it was taken"
        )
        XCTAssertFalse(manager.state.lastReservoirReadingNeedsReport)
    }

    func testHeldReadingIsReportedWhenTheQueueIsAttachedFirst() {
        stubReservoir(units: 75)
        sync()

        let delegate = MockPumpManagerDelegate()
        let readReservoir = expectation(description: "delegate received the held reservoir value")
        delegate.didReadReservoirExpectation = readReservoir

        let queue = attachDelegate(delegate, queueFirst: true)
        wait(for: [readReservoir], timeout: 2.0)
        queue.sync {}

        XCTAssertEqual(delegate.reservoirReadings.map(\.units), [75])
    }

    func testAttachingADelegateDoesNotResendAnAlreadyDeliveredReading() {
        let delegate = MockPumpManagerDelegate()
        let queue = attachDelegate(delegate)

        let readReservoir = expectation(description: "delegate received reservoir value")
        delegate.didReadReservoirExpectation = readReservoir
        stubReservoir(units: 120)
        sync()
        wait(for: [readReservoir], timeout: 2.0)
        queue.sync {}

        delegate.didReadReservoirExpectation = nil
        let second = MockPumpManagerDelegate()
        attachDelegate(second)

        XCTAssertEqual(delegate.reservoirReadings.count, 1)
        XCTAssertTrue(
            second.reservoirReadings.isEmpty,
            "Nothing is owed, so an attaching delegate gets no reservoir call"
        )
    }

    func testAttachingADelegateReportsNothingWhenNoReadingWasEverTaken() {
        let delegate = MockPumpManagerDelegate()
        attachDelegate(delegate)

        XCTAssertTrue(delegate.reservoirReadings.isEmpty)
    }

    func testAttachingADelegateDoesNotReportAReadingNoSyncHasReconciledPast() {
        stubReservoir(units: 60)
        manager.fetchReservoirStatus()

        let delegate = MockPumpManagerDelegate()
        let queue = attachDelegate(delegate)
        queue.sync {}

        XCTAssertTrue(delegate.reservoirReadings.isEmpty)
        XCTAssertTrue(manager.state.lastReservoirReadingNeedsReport, "Held for the next sync, not dropped")
    }

    func testPendingReportSurvivesAStateRoundTrip() throws {
        stubReservoir(units: 90)
        sync()

        let restored = try XCTUnwrap(TandemPumpManagerState(rawValue: manager.state.rawValue))
        XCTAssertEqual(restored.lastReservoirReading?.unitVolume, 90)
        XCTAssertTrue(restored.lastReservoirReadingNeedsReport)

        let relaunched = TandemPumpManager(state: restored, bluetooth: StubPumpBluetooth())
        let delegate = MockPumpManagerDelegate()
        let readReservoir = expectation(description: "delegate received the held reservoir value")
        delegate.didReadReservoirExpectation = readReservoir

        let queue = DispatchQueue(label: "reservoir-report-relaunch-test")
        relaunched.pumpManagerDelegate = delegate
        relaunched.delegateQueue = queue

        wait(for: [readReservoir], timeout: 2.0)
        queue.sync {}

        XCTAssertEqual(delegate.reservoirReadings.map(\.units), [90])
        XCTAssertFalse(relaunched.state.lastReservoirReadingNeedsReport)
    }

    func testAReadingTakenDuringABolusIsReportedWhenTheBolusEndsWithoutASync() throws {
        let clock = ManualClock(Date(timeIntervalSinceReferenceDate: 800_000_000))
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.historyBackfill] = false
        state.pumpState.pumpSerial = 123_456
        state.insulinType = .novolog
        state.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!
        state.basalDose = UnfinalizedDose(basalRate: 1.0, insulinType: .novolog, startDate: clock.now)
        state.hasSyncedBasalRateSchedule = true
        manager = TandemPumpManager(state: state, bluetooth: bluetooth, clock: clock)
        bluetooth.stubBasalPump(profileMilliunits: 1000, tempRateId: 41)
        let delegate = MockPumpManagerDelegate()
        delegate.journalClock = clock
        let queue = attachDelegate(delegate)

        let bolusId = 4100
        bluetooth.stub(BolusPermissionRequest.self, with: BolusPermissionResponse(status: 0, bolusId: bolusId, nackReasonId: 0))
        bluetooth.stub(InitiateBolusRequest.self, with: InitiateBolusResponse(status: 0, bolusId: bolusId, statusTypeId: 0))
        let enacted = expectation(description: "enactBolus")
        manager.enactBolus(decisionId: nil, units: 3.4, activationType: .manualNoRecommendation) { error in
            XCTAssertNil(error)
            enacted.fulfill()
        }
        wait(for: [enacted], timeout: 5)
        queue.sync {}

        clock.advance(by: 60)
        bluetooth.stub(InsulinStatusRequest.self, with: InsulinStatusResponse(currentInsulinAmount: 17, isEstimate: 0, insulinLowAmount: 20))
        manager.fetchReservoirStatus()
        queue.sync {}
        XCTAssertTrue(delegate.reservoirReadings.isEmpty, "Past the boundary until the bolus ends")

        clock.advance(by: 60)
        bluetooth.stub(CurrentBolusStatusRequest.self, with: CurrentBolusStatusResponse(
            statusId: 0, bolusId: 0, timestamp: 0, requestedVolume: 3400, bolusSourceId: 0, bolusTypeBitmask: 0
        ))
        bluetooth.stub(LastBolusStatusRequest.self, with: LastBolusStatusResponse(
            status: 0, bolusId: bolusId, timestamp: 0, deliveredVolume: 3400,
            bolusStatusId: 0, bolusSourceId: 0, bolusTypeBitmask: 0, extendedBolusDuration: 0
        ))
        manager.fetchBolusStatus(fromSync: false)
        queue.sync {}

        XCTAssertEqual(delegate.reservoirReadings.map(\.units), [17])
        XCTAssertTrue(delegate.reservoirReadingsAheadOfTheBoundary.isEmpty)
        XCTAssertFalse(manager.state.lastReservoirReadingNeedsReport)
    }

    func testABatchSentBeforeTheDelegateQueueRunsDoesNotReportTheReadingTwice() {
        let delegate = MockPumpManagerDelegate()
        let queue = attachDelegate(delegate)
        stubReservoir(units: 140)
        manager.fetchReservoirStatus()
        manager.state.lastReconciliation = Date()

        queue.suspend()
        manager.reportReconciliationBoundary()
        manager.reportReconciliationBoundary()
        queue.resume()
        queue.sync {}

        XCTAssertEqual(delegate.reservoirReadings.map(\.units), [140])
    }
}
