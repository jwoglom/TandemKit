import LoopKit
@testable import TandemKit
import XCTest

/// `lastReconciliation` reaches the host only as an argument of `hasNewPumpEvents`, and every
/// other emitter fires on a dose transition.
@available(macOS 13.0, iOS 14.0, *) final class ReconciliationBoundaryDeliveryTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
    }

    override func tearDown() {
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    /// A pump with nothing running: nothing in the driver has a dose to report.
    private func stubQuietSyncResponses() {
        stubReservoir(units: 150)
        bluetooth.stubIdleDelivery()
    }

    private func stubReservoir(units: Int) {
        bluetooth.stub(InsulinStatusRequest.self, with: InsulinStatusResponse(
            currentInsulinAmount: units,
            isEstimate: 0,
            insulinLowAmount: 20
        ))
    }

    /// Drains the queue on the way out so assertions see everything the attach kicked off.
    @discardableResult
    private func attachDelegate(
        _ delegate: MockPumpManagerDelegate,
        queueFirst: Bool = false
    ) -> DispatchQueue {
        let queue = DispatchQueue(label: "reconciliation-boundary-test")

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

    private func runSync(on queue: DispatchQueue?) {
        let synced = expectation(description: "syncPumpData completes")
        manager.syncPumpData { _ in synced.fulfill() }
        wait(for: [synced], timeout: 5.0)
        queue?.sync {}
    }

    // MARK: - Quiet syncs

    func testQuietSyncReportsTheNewBoundaryToTheHost() {
        let delegate = MockPumpManagerDelegate()
        let queue = attachDelegate(delegate)
        stubQuietSyncResponses()

        runSync(on: queue)

        let boundary = try? XCTUnwrap(manager.state.lastReconciliation)
        XCTAssertNotNil(boundary, "A sync the pump answered must stamp the boundary")
        XCTAssertEqual(
            delegate.pumpEventBatches.last?.lastReconciliation,
            boundary,
            "A sync with no dose to report must still carry its boundary to the host"
        )
    }

    /// An empty replacing batch purges every mutable row Trio holds.
    func testQuietSyncCarriesNoEventsAndDoesNotReplacePendingOnes() {
        let delegate = MockPumpManagerDelegate()
        let queue = attachDelegate(delegate)
        stubQuietSyncResponses()

        runSync(on: queue)

        let batches = delegate.pumpEventBatches
        XCTAssertFalse(batches.isEmpty, "The sync must have reported something")
        for batch in batches {
            XCTAssertTrue(batch.events.isEmpty, "A quiet sync has no dose to report")
            XCTAssertFalse(
                batch.replacePendingEvents,
                "A boundary-only report must not purge the host's pending mutable doses"
            )
        }
    }

    func testSyncThePumpAnswersNothingToReportsNoBoundary() {
        let delegate = MockPumpManagerDelegate()
        let queue = attachDelegate(delegate)

        runSync(on: queue)

        XCTAssertNil(manager.state.lastReconciliation)
        XCTAssertTrue(delegate.pumpEventBatches.isEmpty, "An unanswered sync must not report a boundary")
    }

    // MARK: - Only the delivery reads move it (#449)

    func testASyncWhoseDeliveryReadsGoUnansweredReportsNoBoundaryAndNoReservoirReading() {
        let delegate = MockPumpManagerDelegate()
        let queue = attachDelegate(delegate)
        let earlier = Date().addingTimeInterval(-.minutes(5))
        manager.state.lastReconciliation = earlier
        stubReservoir(units: 150)
        bluetooth.stub(CurrentBatteryV1Request.self, with: CurrentBatteryV1Response(currentBatteryAbc: 20, currentBatteryIbc: 80))

        runSync(on: queue)

        XCTAssertEqual(manager.state.lastReconciliation, earlier)
        XCTAssertTrue(delegate.pumpEventBatches.isEmpty, "\(delegate.pumpEventBatches)")
        XCTAssertTrue(delegate.reservoirReadings.isEmpty, "Loop counts reservoir drops past its boundary")
        XCTAssertEqual(manager.reservoirLevel?.unitVolume, 150, "The driver's own status still shows it")
        XCTAssertTrue(manager.state.lastReservoirReadingNeedsReport)
    }

    func testASyncReportsItsReservoirReadingAfterTheBoundaryThatCoversIt() throws {
        let delegate = MockPumpManagerDelegate()
        let queue = attachDelegate(delegate)
        stubQuietSyncResponses()

        runSync(on: queue)

        let boundary = try XCTUnwrap(manager.state.lastReconciliation)
        let reading = try XCTUnwrap(delegate.reservoirReadings.last)
        XCTAssertLessThanOrEqual(reading.date, boundary)
        let kinds = delegate.journal.compactMap { entry -> String? in
            switch entry.kind {
            case .pumpEvents: return "batch"
            case .reservoirReading: return "reservoir"
            default: return nil
            }
        }
        XCTAssertEqual(kinds, ["batch", "reservoir"])
        XCTAssertTrue(delegate.reservoirReadingsAheadOfTheBoundary.isEmpty)
        XCTAssertFalse(manager.state.lastReservoirReadingNeedsReport)
    }

    func testAReadingHeldThroughAnUnreconciledSyncIsReportedByTheNextReconciledOne() throws {
        let delegate = MockPumpManagerDelegate()
        let queue = attachDelegate(delegate)
        stubReservoir(units: 150)
        runSync(on: queue)
        let heldAt = try XCTUnwrap(manager.reservoirLevel?.startDate)

        bluetooth.stub(InsulinStatusRequest.self) { _ in nil }
        bluetooth.stubIdleDelivery()
        runSync(on: queue)

        XCTAssertEqual(delegate.reservoirReadings.map(\.units), [150])
        XCTAssertEqual(delegate.reservoirReadings.last?.date, heldAt, "The held reading keeps the time it was taken")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(manager.state.lastReconciliation), heldAt)
        XCTAssertTrue(delegate.reservoirReadingsAheadOfTheBoundary.isEmpty)
    }

    func testAStandaloneReservoirReadMovesNoBoundaryAndWaitsForTheNextSync() throws {
        let delegate = MockPumpManagerDelegate()
        let queue = attachDelegate(delegate)
        stubQuietSyncResponses()
        runSync(on: queue)
        let boundary = manager.state.lastReconciliation
        let batchesBefore = delegate.pumpEventBatches.count

        stubReservoir(units: 149)
        manager.fetchReservoirStatus()
        queue.sync {}

        XCTAssertEqual(manager.state.lastReconciliation, boundary, "A reservoir level says nothing about bolus or basal state")
        XCTAssertEqual(delegate.pumpEventBatches.count, batchesBefore)
        XCTAssertEqual(delegate.reservoirReadings.map(\.units), [150])
        XCTAssertEqual(manager.reservoirLevel?.unitVolume, 149)

        runSync(on: queue)

        XCTAssertEqual(delegate.reservoirReadings.map(\.units), [150, 149])
        XCTAssertTrue(delegate.reservoirReadingsAheadOfTheBoundary.isEmpty)
    }

    func testARemainingInsulinEventMovesNoBoundaryAndReportsNothing() {
        let delegate = MockPumpManagerDelegate()
        let queue = attachDelegate(delegate)
        let earlier = Date().addingTimeInterval(-.minutes(2))
        manager.state.lastReconciliation = earlier
        stubQuietSyncResponses()

        let handled = expectation(description: "qualifying events handled")
        manager.handleQualifyingEvents(events: [.remainingInsulin]) { handled.fulfill() }
        wait(for: [handled], timeout: 5.0)
        queue.sync {}

        XCTAssertTrue(bluetooth.didSend(InsulinStatusRequest.self))
        XCTAssertEqual(manager.state.lastReconciliation, earlier)
        XCTAssertTrue(delegate.pumpEventBatches.isEmpty, "\(delegate.pumpEventBatches)")
        XCTAssertTrue(delegate.reservoirReadings.isEmpty)
    }

    // MARK: - Emitted before the host adopted the manager

    func testSyncBeforeADelegateAttachesIsReplayedWhenOneDoes() {
        stubQuietSyncResponses()

        // The pairing sync runs before the host adopts the manager.
        runSync(on: nil)

        let boundary = manager.state.lastReconciliation
        XCTAssertNotNil(boundary)
        XCTAssertGreaterThan(
            manager.heldPumpEventBatchCount,
            0,
            "A report with nowhere to go must be held, not dropped"
        )

        let delegate = MockPumpManagerDelegate()
        let queue = attachDelegate(delegate)

        XCTAssertEqual(
            delegate.pumpEventBatches.last?.lastReconciliation,
            boundary,
            "The held report keeps the boundary it was emitted with"
        )
        XCTAssertEqual(manager.heldPumpEventBatchCount, 0)
        XCTAssertEqual(delegate.reservoirReadings.count, 1)
        XCTAssertTrue(delegate.reservoirReadingsAheadOfTheBoundary.isEmpty, "The held boundary goes out ahead of the held reading")
        queue.sync {}
    }

    func testHeldReportsAreReplayedWhenTheQueueIsAttachedFirst() {
        stubQuietSyncResponses()
        runSync(on: nil)

        let delegate = MockPumpManagerDelegate()
        let queue = attachDelegate(delegate, queueFirst: true)

        XCTAssertFalse(delegate.pumpEventBatches.isEmpty)
        XCTAssertEqual(manager.heldPumpEventBatchCount, 0)
        queue.sync {}
    }

    func testDoseEventsEmittedWithoutADelegateAreReplayedInOrder() {
        let suspendDate = Date().addingTimeInterval(-120)
        let resumeDate = Date().addingTimeInterval(-60)

        manager.emitPumpEvents([NewPumpEvent.siteChange(date: suspendDate)], replacePendingEvents: false)
        manager.emitPumpEvents([NewPumpEvent.cartridgeChange(date: resumeDate)], replacePendingEvents: false)

        XCTAssertEqual(manager.heldPumpEventBatchCount, 2)

        let delegate = MockPumpManagerDelegate()
        let queue = attachDelegate(delegate)

        XCTAssertEqual(
            delegate.pumpEventBatches.map(\.events.count),
            [1, 1],
            "Each held batch is replayed whole"
        )
        XCTAssertEqual(
            delegate.pumpEvents.map(\.date),
            [suspendDate, resumeDate],
            "Held events are replayed in the order they were emitted"
        )
        queue.sync {}
    }

    func testAttachingADelegateDoesNotReplayTheSameReportTwice() {
        stubQuietSyncResponses()
        runSync(on: nil)

        let delegate = MockPumpManagerDelegate()
        let queue = attachDelegate(delegate)
        let afterAttach = delegate.pumpEventBatches.count

        // deliverStateMissedByTheDelegate runs from both setters.
        manager.pumpManagerDelegate = delegate
        queue.sync {}

        XCTAssertEqual(delegate.pumpEventBatches.count, afterAttach)
    }

    func testASyncAfterAttachSendsHeldReportsFirst() throws {
        stubQuietSyncResponses()
        runSync(on: nil)
        let pairingBoundary = manager.state.lastReconciliation

        let delegate = MockPumpManagerDelegate()
        let queue = attachDelegate(delegate)
        runSync(on: queue)

        let boundaries = delegate.pumpEventBatches.compactMap(\.lastReconciliation)
        XCTAssertTrue(
            boundaries.contains(try XCTUnwrap(pairingBoundary)),
            "The boundary held from before the attach must still reach the host"
        )
        XCTAssertEqual(boundaries.last, manager.state.lastReconciliation)
        XCTAssertEqual(boundaries, boundaries.sorted(), "Boundaries must reach the host in order")
    }
}
