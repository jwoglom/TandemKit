import XCTest
@testable import TandemKit
@testable import TandemCore
import LoopKit

@available(macOS 13.0, iOS 14.0, *)
final class TandemPumpManagerConsentTests: XCTestCase {
    override func tearDown() {
        PumpStateSupplier.disableActionsAffectingInsulinDelivery()
        PumpStateSupplier.disableConnectionSharing()
        super.tearDown()
    }

    func testConfigureDeliveryActionsUpdatesSupplierStateAndDelegate() throws {
        PumpStateSupplier.disableActionsAffectingInsulinDelivery()
        let state = TandemPumpManagerState(pumpState: nil)
        let manager = TandemPumpManager(state: state)

        let delegate = MockPumpManagerDelegate()
        let queue = DispatchQueue(label: "delivery-toggle-test-queue")
        manager.delegateQueue = queue
        manager.pumpManagerDelegate = delegate

        let enableExpectation = expectation(description: "enable delivery actions")
        delegate.didUpdateStateExpectation = enableExpectation

        manager.configureDeliveryActions(true)

        wait(for: [enableExpectation], timeout: 1.0)

        XCTAssertTrue(PumpStateSupplier.actionsAffectingInsulinDeliveryEnabled())
        XCTAssertTrue(manager.insulinDeliveryActionsEnabled)

        let enabledState = try XCTUnwrap(TandemPumpManagerState(rawValue: manager.rawState))
        XCTAssertTrue(enabledState.insulinDeliveryActionsEnabled)

        let disableExpectation = expectation(description: "disable delivery actions")
        delegate.didUpdateStateExpectation = disableExpectation

        manager.configureDeliveryActions(false)

        wait(for: [disableExpectation], timeout: 1.0)

        XCTAssertFalse(PumpStateSupplier.actionsAffectingInsulinDeliveryEnabled())
        XCTAssertFalse(manager.insulinDeliveryActionsEnabled)

        let disabledState = try XCTUnwrap(TandemPumpManagerState(rawValue: manager.rawState))
        XCTAssertFalse(disabledState.insulinDeliveryActionsEnabled)
    }

    func testConfigureConnectionSharingUpdatesSupplierStateAndDelegate() throws {
        PumpStateSupplier.disableConnectionSharing()
        let state = TandemPumpManagerState(pumpState: nil)
        let manager = TandemPumpManager(state: state)

        let delegate = MockPumpManagerDelegate()
        let queue = DispatchQueue(label: "connection-toggle-test-queue")
        manager.delegateQueue = queue
        manager.pumpManagerDelegate = delegate

        let enableExpectation = expectation(description: "enable connection sharing")
        delegate.didUpdateStateExpectation = enableExpectation

        manager.configureConnectionSharing(true)

        wait(for: [enableExpectation], timeout: 1.0)

        XCTAssertTrue(PumpStateSupplier.connectionSharingEnabled())
        XCTAssertTrue(manager.connectionSharingEnabled)

        let enabledState = try XCTUnwrap(TandemPumpManagerState(rawValue: manager.rawState))
        XCTAssertTrue(enabledState.connectionSharingEnabled)

        let disableExpectation = expectation(description: "disable connection sharing")
        delegate.didUpdateStateExpectation = disableExpectation

        manager.configureConnectionSharing(false)

        wait(for: [disableExpectation], timeout: 1.0)

        XCTAssertFalse(PumpStateSupplier.connectionSharingEnabled())
        XCTAssertFalse(manager.connectionSharingEnabled)

        let disabledState = try XCTUnwrap(TandemPumpManagerState(rawValue: manager.rawState))
        XCTAssertFalse(disabledState.connectionSharingEnabled)
    }
}
