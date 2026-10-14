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
}
