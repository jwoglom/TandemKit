import LoopKit
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class StateUpdateDeliveryTests: XCTestCase {
    private var manager: TandemPumpManager!
    private var delegateQueue: DispatchQueue!

    override func setUp() {
        super.setUp()
        delegateQueue = DispatchQueue(label: "state-update-delivery-test")
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: StubPumpBluetooth())
    }

    override func tearDown() {
        manager = nil
        delegateQueue = nil
        super.tearDown()
    }

    func testAStateUpdateBetweenAttachingTheDelegateAndItsQueueArrivesOnTheQueue() {
        let delegate = MockPumpManagerDelegate()

        // Trio's order, with the Bluetooth power-on update landing between the two setters.
        manager.pumpManagerDelegate = delegate
        manager.notifyDelegateStateUpdated()
        manager.delegateQueue = delegateQueue

        drainMainQueue()
        delegateQueue.sync {}

        XCTAssertEqual(delegate.didUpdateStateCount, 1)
        XCTAssertEqual(delegate.statusUpdates.count, 1)
    }

    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 5.0)
    }
}
