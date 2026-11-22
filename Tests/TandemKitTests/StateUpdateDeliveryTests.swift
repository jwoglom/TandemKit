import LoopKit
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class StateUpdateDeliveryTests: XCTestCase {
    private var manager: TandemPumpManager!

    override func setUp() {
        super.setUp()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: StubPumpBluetooth())
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    func testAttachingLeavesSavingTheStateToTheHost() {
        let delegate = MockPumpManagerDelegate()

        manager.pumpManagerDelegate = delegate
        manager.waitForDelegateCalls()

        XCTAssertEqual(delegate.didUpdateStateCount, 0, "Loop and Trio save rawValue as they attach; a second save from the manager's call races theirs")

        manager.notifyDelegateStateUpdated()
        manager.waitForDelegateCalls()

        XCTAssertEqual(delegate.didUpdateStateCount, 1, "a change after attaching is saved as usual")
    }
}
