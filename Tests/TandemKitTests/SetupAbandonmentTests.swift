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
        let bluetooth = StubPumpBluetooth()
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)

        XCTAssertFalse(manager.canNotifyDelegate)

        let delegate = MockPumpManagerDelegate()
        manager.pumpManagerDelegate = delegate
        XCTAssertFalse(manager.canNotifyDelegate, "a delegate without a queue is not somewhere events can go")
        XCTAssertEqual(bluetooth.adoptedCount, 0)

        manager.delegateQueue = DispatchQueue(label: "setup-abandonment-test")
        XCTAssertTrue(manager.canNotifyDelegate)
        XCTAssertEqual(bluetooth.adoptedCount, 1, "the transport is told, since Bluetooth may have come on first")
        withExtendedLifetime(delegate) {}
    }

    func testAHostThatSetsNoQueueIsReportedToOnTheMainQueue() {
        let bluetooth = StubPumpBluetooth()
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        let delegate = MockPumpManagerDelegate()

        // Loop next-dev's order: a delegate, and no queue.
        manager.pumpManagerDelegate = delegate
        waitPastTheQueueGrace()

        XCTAssertTrue(manager.canNotifyDelegate)
        // Not `=== DispatchQueue.main`: on Linux each read of `.main` is a new wrapper.
        let ranOnMain = expectation(description: "a block on the delegate queue runs on the main thread")
        manager.delegateQueue.async {
            XCTAssertTrue(Thread.isMainThread)
            ranOnMain.fulfill()
        }
        wait(for: [ranOnMain], timeout: 5)
        XCTAssertEqual(bluetooth.adoptedCount, 1)
        withExtendedLifetime(delegate) {}
    }

    func testAQueueSetRightAfterTheDelegateIsKept() {
        let bluetooth = StubPumpBluetooth()
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        let delegate = MockPumpManagerDelegate()
        let queue = DispatchQueue(label: "setup-abandonment-test")

        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = queue
        waitPastTheQueueGrace()

        XCTAssertTrue(manager.delegateQueue === queue)
        XCTAssertEqual(bluetooth.adoptedCount, 1, "adopted once, when the queue was set")
        withExtendedLifetime(delegate) {}
    }

    func testAManagerWhoseDelegateWasClearedIsNotAdoptedOnTheMainQueue() {
        let bluetooth = StubPumpBluetooth()
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        let delegate = MockPumpManagerDelegate()

        manager.pumpManagerDelegate = delegate
        manager.pumpManagerDelegate = nil
        waitPastTheQueueGrace()

        XCTAssertFalse(manager.canNotifyDelegate)
        XCTAssertEqual(bluetooth.adoptedCount, 0)
        withExtendedLifetime(delegate) {}
    }

    private func waitPastTheQueueGrace() {
        let waited = expectation(description: "past the unset delegate queue grace")
        DispatchQueue.main.asyncAfter(deadline: .now() + TandemPumpManager.unsetDelegateQueueGrace + 0.2) {
            waited.fulfill()
        }
        wait(for: [waited], timeout: TandemPumpManager.unsetDelegateQueueGrace + 5)
    }
}
