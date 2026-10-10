import CoreBluetooth
import LoopKit
@testable import TandemKit
import XCTest

/// A pump that keeps ending the handshake: after `jpakeFailureLimit` in a row the driver stops
/// reconnecting on its own and says why, instead of retrying forever against it.
@available(macOS 13.0, iOS 14.0, *) final class JpakeFailureLimitTests: XCTestCase {
    private var bluetooth: TandemBluetoothManager!
    private var manager: TandemPumpManager!

    override func setUp() {
        super.setUp()
        bluetooth = TandemBluetoothManager()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
    }

    override func tearDown() {
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func failHandshakes(_ count: Int) {
        for _ in 0 ..< count {
            bluetooth.recordJpakeFailure()
        }
    }

    private func reachTheLimit() {
        failHandshakes(TandemBluetoothManager.jpakeFailureLimit)
    }

    /// Without a radio, a connect job that actually runs fails and marks the link down; one that is
    /// skipped leaves it as it was. That is the difference these tests read.
    private func runConnectJob(_ start: (@escaping (Error?) -> Void) -> Void) {
        manager.state.isConnected = true
        let finished = expectation(description: "connect job")
        start { _ in finished.fulfill() }
        wait(for: [finished], timeout: 5.0)
    }

    private func attachDelegate() -> MockPumpManagerDelegate {
        let delegate = MockPumpManagerDelegate()
        manager.delegateQueue = DispatchQueue(label: "jpake-failure-limit-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue.sync {}
        return delegate
    }

    // MARK: - Counting

    func testTwoFailedHandshakesAreNotEnoughToStop() {
        failHandshakes(TandemBluetoothManager.jpakeFailureLimit - 1)

        XCTAssertFalse(bluetooth.isJpakeFailureLimitReached)
    }

    func testThreeFailedHandshakesInARowReachTheLimit() {
        XCTAssertEqual(TandemBluetoothManager.jpakeFailureLimit, 3)

        reachTheLimit()

        XCTAssertTrue(bluetooth.isJpakeFailureLimitReached)
    }

    func testASuccessfulHandshakeBetweenFailuresStartsTheCountAgain() {
        failHandshakes(2)
        bluetooth.recordJpakeSuccess()
        failHandshakes(2)

        XCTAssertFalse(bluetooth.isJpakeFailureLimitReached)

        failHandshakes(1)

        XCTAssertTrue(bluetooth.isJpakeFailureLimitReached)
    }

    func testASuccessfulHandshakeClearsTheLimit() {
        reachTheLimit()

        bluetooth.recordJpakeSuccess()

        XCTAssertFalse(bluetooth.isJpakeFailureLimitReached)
    }

    func testFailuresPastTheLimitKeepItReached() {
        reachTheLimit()
        failHandshakes(2)

        XCTAssertTrue(bluetooth.isJpakeFailureLimitReached)
    }

    func testTurningBluetoothBackOnClearsTheLimit() {
        reachTheLimit()

        bluetooth.handleBluetoothStateChange(.poweredOn)

        XCTAssertFalse(bluetooth.isJpakeFailureLimitReached)
    }

    func testAConcurrentRunOfFailuresStillCountsEveryOne() {
        DispatchQueue.concurrentPerform(iterations: 90) { _ in
            bluetooth.recordJpakeFailure()
        }

        XCTAssertTrue(bluetooth.isJpakeFailureLimitReached)
    }

    // MARK: - What it stops

    func testAnAutomaticReconnectIsSkippedOnceTheLimitIsReached() {
        reachTheLimit()

        runConnectJob(bluetooth.reconnectAutomatically)

        XCTAssertTrue(manager.state.isConnected, "no connect attempt was made")
    }

    func testAnAutomaticReconnectStillRunsBeforeTheLimit() {
        failHandshakes(TandemBluetoothManager.jpakeFailureLimit - 1)

        runConnectJob(bluetooth.reconnectAutomatically)

        XCTAssertFalse(manager.state.isConnected, "a connect attempt was made")
    }

    func testAHostCommandStillTriesOnceTheLimitIsReached() {
        reachTheLimit()

        runConnectJob(bluetooth.ensureConnected)

        XCTAssertFalse(manager.state.isConnected, "a connect attempt was made")
    }

    // MARK: - What the host is told

    func testTheDriverReportsTheProblemOnceTheLimitIsReached() {
        XCTAssertNotEqual(manager.connectionIssue, .handshakeFailing)

        reachTheLimit()

        XCTAssertEqual(manager.connectionIssue, .handshakeFailing)
        XCTAssertEqual(manager.sustainedConnectionIssue, .handshakeFailing)
    }

    func testReachingTheLimitIsPublishedToTheHostAndNotBefore() {
        let delegate = attachDelegate()
        let before = delegate.didUpdateStateCount

        failHandshakes(TandemBluetoothManager.jpakeFailureLimit - 1)
        manager.delegateQueue.sync {}
        XCTAssertEqual(delegate.didUpdateStateCount, before)

        failHandshakes(1)
        manager.delegateQueue.sync {}
        XCTAssertGreaterThan(delegate.didUpdateStateCount, before)
    }

    func testClearingTheLimitIsPublishedToTheHostButAnOrdinarySuccessIsNot() {
        let delegate = attachDelegate()
        failHandshakes(1)
        bluetooth.recordJpakeSuccess()
        manager.delegateQueue.sync {}
        let afterOrdinarySuccess = delegate.didUpdateStateCount

        reachTheLimit()
        manager.delegateQueue.sync {}
        let atTheLimit = delegate.didUpdateStateCount
        bluetooth.recordJpakeSuccess()
        manager.delegateQueue.sync {}

        XCTAssertGreaterThan(atTheLimit, afterOrdinarySuccess)
        XCTAssertGreaterThan(delegate.didUpdateStateCount, atTheLimit)
    }
}
