import Foundation
@testable import TandemKit
import XCTest

/// A setup flow left before the host was handed its manager takes the manager's transport down with
/// it, so it cannot go on pairing in the background and hold the pump's one link (#603).
@available(macOS 13.0, iOS 14.0, *) final class SetupAbandonmentTests: XCTestCase {
    func testAbandoningSetupDeactivatesTheTransport() {
        let bluetooth = StubPumpBluetooth()
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)

        manager.abandonSetup()

        XCTAssertEqual(bluetooth.deactivateCount, 1)
    }

    func testAManagerIsAdoptedOnceAHostHasSetItsDelegate() {
        let bluetooth = StubPumpBluetooth()
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)

        XCTAssertFalse(manager.canNotifyDelegate)

        let delegate = MockPumpManagerDelegate()
        manager.pumpManagerDelegate = delegate

        XCTAssertTrue(manager.canNotifyDelegate)
        XCTAssertEqual(bluetooth.adoptedCount, 1, "the transport is told, since Bluetooth may have come on first")
        withExtendedLifetime(delegate) {}
    }

    func testAManagerWhoseDelegateWasClearedReportsToNoHost() {
        let bluetooth = StubPumpBluetooth()
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        let delegate = MockPumpManagerDelegate()

        manager.pumpManagerDelegate = delegate
        manager.pumpManagerDelegate = nil

        XCTAssertFalse(manager.canNotifyDelegate)
        withExtendedLifetime(delegate) {}
    }
}
