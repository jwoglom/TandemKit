import LoopKit
@testable import TandemKit
import XCTest

/// `didReadReservoirValue` is the only channel the reservoir has to the host app, and it is
/// one-shot: nothing re-derives it the way the pump status is re-sent on every state change or
/// the alert set is re-reconciled on every fetch. The driver reads the reservoir before the host
/// adopts it — pairing ends in a full `syncPumpData` — so a dropped call leaves the host showing
/// a stale cartridge level until some later read happens to land with a delegate attached.
@available(macOS 13.0, iOS 14.0, *) final class ReservoirReportDeliveryTests: XCTestCase {
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

    private func stubReservoir(units: Int) {
        bluetooth.stub(InsulinStatusRequest.self, with: InsulinStatusResponse(
            currentInsulinAmount: units,
            isEstimate: 0,
            insulinLowAmount: 20
        ))
    }

    /// Attaches a delegate the way a host does, and waits for the queue to drain so the
    /// assertions see everything the attach kicked off.
    @discardableResult
    private func attachDelegate(
        _ delegate: MockPumpManagerDelegate,
        queueFirst: Bool = false
    ) -> DispatchQueue {
        let queue = DispatchQueue(label: "reservoir-report-test")

        if queueFirst {
            manager.delegateQueue = queue
            manager.pumpManagerDelegate = delegate
        } else {
            // Trio's order: the delegate lands before the queue it must be called on.
            manager.pumpManagerDelegate = delegate
            manager.delegateQueue = queue
        }

        queue.sync {}
        return queue
    }

    func testReadingIsReportedImmediatelyWhenADelegateIsAttached() {
        let delegate = MockPumpManagerDelegate()
        let queue = attachDelegate(delegate)

        let readReservoir = expectation(description: "delegate received reservoir value")
        delegate.didReadReservoirExpectation = readReservoir
        stubReservoir(units: 150)

        manager.fetchReservoirStatus()
        wait(for: [readReservoir], timeout: 2.0)
        queue.sync {}

        XCTAssertEqual(delegate.reservoirReadings.map(\.units), [150])
        XCTAssertFalse(
            manager.state.lastReservoirReadingNeedsReport,
            "A delivered reading must not stay queued for redelivery"
        )
    }

    /// The pairing case: `onPairSuccess` syncs on a manager the host has not adopted yet.
    func testReadingTakenWithoutADelegateIsReportedWhenOneAttaches() {
        stubReservoir(units: 50)

        manager.fetchReservoirStatus()

        XCTAssertEqual(manager.reservoirLevel?.unitVolume, 50, "The driver's own state is up to date")
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
            "The held reading keeps the time it was actually taken"
        )
        XCTAssertFalse(manager.state.lastReservoirReadingNeedsReport)
    }

    /// LoopKit's own order — queue first, then delegate — has to work too.
    func testHeldReadingIsReportedWhenTheQueueIsAttachedFirst() {
        stubReservoir(units: 75)
        manager.fetchReservoirStatus()

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
        manager.fetchReservoirStatus()
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

    /// A failed read leaves nothing to hand over; the previous reading was already delivered.
    func testAttachingADelegateReportsNothingWhenNoReadingWasEverTaken() {
        let delegate = MockPumpManagerDelegate()
        attachDelegate(delegate)

        XCTAssertTrue(delegate.reservoirReadings.isEmpty)
    }

    /// The flag rides along in the persisted state, so a reading taken moments before the app is
    /// killed is still owed to the host on the next launch.
    func testPendingReportSurvivesAStateRoundTrip() throws {
        stubReservoir(units: 90)
        manager.fetchReservoirStatus()

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
