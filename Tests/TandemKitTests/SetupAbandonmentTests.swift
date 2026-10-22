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

    func testAManagerIsAdoptedOnceAHostHasSetItsDelegateAndQueue() {
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: StubPumpBluetooth())

        XCTAssertFalse(manager.canNotifyDelegate)

        let delegate = MockPumpManagerDelegate()
        manager.pumpManagerDelegate = delegate
        XCTAssertFalse(manager.canNotifyDelegate, "a delegate without a queue is not somewhere events can go")

        manager.delegateQueue = DispatchQueue(label: "setup-abandonment-test")
        XCTAssertTrue(manager.canNotifyDelegate)
        withExtendedLifetime(delegate) {}
    }
}
