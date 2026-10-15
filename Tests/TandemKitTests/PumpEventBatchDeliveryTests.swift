import LoopKit
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class PumpEventBatchDeliveryTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var queue: DispatchQueue!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        delegate = MockPumpManagerDelegate()
        queue = DispatchQueue(label: "pump-event-batch-delivery-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = queue
        queue.sync {}
    }

    override func tearDown() {
        queue.sync {}
        manager = nil
        delegate = nil
        queue = nil
        bluetooth = nil
        super.tearDown()
    }

    private func emitMarker(minutesAgo: Double) {
        manager.emitPumpEvents(
            [NewPumpEvent.siteChange(date: Date().addingTimeInterval(-minutesAgo * 60))],
            replacePendingEvents: false
        )
    }

    func testABatchWaitsUntilTheHostHasStoredTheOneBeforeIt() {
        delegate.holdsPumpEventCompletions = true

        emitMarker(minutesAgo: 2)
        emitMarker(minutesAgo: 1)
        queue.sync {}

        XCTAssertEqual(delegate.pumpEventBatches.count, 1)

        delegate.finishHeldPumpEventBatch()
        queue.sync {}

        XCTAssertEqual(delegate.pumpEventBatches.count, 2)
    }

    func testAHostThatStoresInsideTheCallGetsEveryBatchInOnePass() {
        emitMarker(minutesAgo: 3)
        emitMarker(minutesAgo: 2)
        emitMarker(minutesAgo: 1)
        queue.sync {}

        XCTAssertEqual(delegate.pumpEventBatches.count, 3)
    }

    func testBatchesReachTheHostInTheOrderTheyWereEmitted() {
        delegate.holdsPumpEventCompletions = true
        let dates = [3.0, 2.0, 1.0].map { Date().addingTimeInterval(-$0 * 60) }

        for date in dates {
            manager.emitPumpEvents([NewPumpEvent.siteChange(date: date)], replacePendingEvents: false)
        }
        queue.sync {}
        while delegate.heldPumpEventCompletionCount > 0 {
            delegate.finishHeldPumpEventBatch()
            queue.sync {}
        }

        XCTAssertEqual(delegate.pumpEvents.map(\.date), dates)
    }

    func testAHostThatNeverFinishesGetsTheNextBatchAfterTheTimeout() {
        delegate.holdsPumpEventCompletions = true
        manager.pumpEventBatchCompletionTimeout = 0.2
        let delivered = expectation(description: "both batches delivered")
        delivered.expectedFulfillmentCount = 2
        delegate.didReceivePumpEventsExpectation = delivered

        emitMarker(minutesAgo: 2)
        emitMarker(minutesAgo: 1)

        wait(for: [delivered], timeout: 5)
    }

    func testACompletionAfterTheTimeoutDoesNotReleaseABatchEarly() {
        delegate.holdsPumpEventCompletions = true
        // Long enough that the second batch's own timeout cannot fire before the assertion.
        manager.pumpEventBatchCompletionTimeout = 1
        let twoDelivered = expectation(description: "two batches delivered")
        twoDelivered.expectedFulfillmentCount = 2
        delegate.didReceivePumpEventsExpectation = twoDelivered

        emitMarker(minutesAgo: 3)
        emitMarker(minutesAgo: 2)
        emitMarker(minutesAgo: 1)
        wait(for: [twoDelivered], timeout: 5)
        delegate.didReceivePumpEventsExpectation = nil

        // The first batch's completion, after its timeout released the second.
        delegate.finishHeldPumpEventBatch()
        queue.sync {}

        XCTAssertEqual(delegate.pumpEventBatches.count, 2)
    }

    func testTheHostIsToldOfTheDeletionOnlyOnceItHasStoredTheBatchesBeforeIt() {
        delegate.holdsPumpEventCompletions = true
        emitMarker(minutesAgo: 1)
        let deactivated = expectation(description: "prepareForDeactivation completes")

        manager.prepareForDeactivation { _ in deactivated.fulfill() }
        queue.sync {}

        XCTAssertEqual(delegate.willDeactivateCount, 0)

        delegate.finishHeldPumpEventBatch()
        wait(for: [deactivated], timeout: 5)

        XCTAssertEqual(delegate.willDeactivateCount, 1)
    }

    func testAReservoirReadingWaitsForTheBatchBeforeIt() {
        delegate.holdsPumpEventCompletions = true
        let date = Date()
        manager.state.lastReconciliation = date
        manager.state.lastReservoirReading = SimpleReservoirValue(startDate: date, unitVolume: 120)
        manager.state.lastReservoirReadingNeedsReport = true

        manager.reportReconciliationBoundary()
        manager.flushPendingReservoirReading()
        queue.sync {}

        XCTAssertTrue(delegate.reservoirReadings.isEmpty)

        delegate.finishHeldPumpEventBatch()
        queue.sync {}

        XCTAssertEqual(delegate.reservoirReadings.map(\.units), [120])
    }
}
