import LoopKit
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class StateNotificationConcurrencyTests: XCTestCase {
    func testConcurrentStateNotificationsDoNotOverReleaseTheLastPublishedState() {
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: StubPumpBluetooth())
        // A class-backed dose, so each published snapshot owns a reference that a racing swap
        // would release twice.
        manager.state.basalDose = UnfinalizedDose(basalRate: 0.85, insulinType: nil, startDate: Date())

        DispatchQueue.concurrentPerform(iterations: 20000) { _ in
            manager.notifyDelegateStateUpdated()
        }

        XCTAssertEqual(manager.state.basalDose.value, 0.85)
    }

    func testConcurrentStateWritesDoNotOverReleaseTheDosesTheyReplace() {
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: StubPumpBluetooth())

        DispatchQueue.concurrentPerform(iterations: 20000) { index in
            manager.state.bolusDose = UnfinalizedDose(basalRate: Double(index), insulinType: nil, startDate: Date())
            _ = manager.state.bolusDose?.value
        }

        XCTAssertNotNil(manager.state.bolusDose)
    }

    func testConcurrentInPlaceUpdatesAreNotLost() {
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: StubPumpBluetooth())
        manager.state.quickBolusStatus = 0

        DispatchQueue.concurrentPerform(iterations: 20000) { _ in
            manager.state.quickBolusStatus! += 1
        }

        XCTAssertEqual(manager.state.quickBolusStatus, 20000)
    }
}
