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

    /// A pump answering only the reservoir read: nothing in the driver has a dose to report.
    private func stubQuietSyncResponses() {
        bluetooth.stub(InsulinStatusRequest.self, with: InsulinStatusResponse(
            currentInsulinAmount: 150,
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

    /// A batch that replaced the host's pending events would purge a running bolus.
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

    func testStandaloneReservoirReadReportsItsOwnStamp() {
        let delegate = MockPumpManagerDelegate()
        let queue = attachDelegate(delegate)
        stubQuietSyncResponses()

        manager.fetchReservoirStatus()
        queue.sync {}

        XCTAssertEqual(
            delegate.pumpEventBatches.last?.lastReconciliation,
            manager.state.lastReconciliation,
            "A reservoir read that moves the boundary must tell the host it moved"
        )
    }

    func testQualifyingEventFetchReportsTheBoundary() {
        let delegate = MockPumpManagerDelegate()
        let queue = attachDelegate(delegate)
        stubQuietSyncResponses()

        let handled = expectation(description: "qualifying events handled")
        manager.handleQualifyingEvents(events: [.remainingInsulin]) { handled.fulfill() }
        wait(for: [handled], timeout: 5.0)
        queue.sync {}

        XCTAssertEqual(
            delegate.pumpEventBatches.last?.lastReconciliation,
            manager.state.lastReconciliation
        )
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

        // The pairing sync reports twice (the reservoir read stamps, then the sync does).
        let boundaries = delegate.pumpEventBatches.compactMap(\.lastReconciliation)
        XCTAssertTrue(
            boundaries.contains(try XCTUnwrap(pairingBoundary)),
            "The boundary held from before the attach must still reach the host"
        )
        XCTAssertEqual(boundaries.last, manager.state.lastReconciliation)
        XCTAssertEqual(boundaries, boundaries.sorted(), "Boundaries must reach the host in order")
    }
}
