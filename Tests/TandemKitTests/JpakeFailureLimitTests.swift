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
        waitForTheCentralsFirstState()
    }

    /// The real central reports its first state on the manager's queue when it likes, and any but
    /// poweredOn marks the link down, which `runConnectJob` reads as an attempt the test never made.
    private func waitForTheCentralsFirstState() {
        #if !os(Linux) && !TANDEMKIT_VIRTUAL_PUMP
            let reported = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in self.bluetooth.manager?.state != .unknown },
                object: nil
            )
            guard XCTWaiter().wait(for: [reported], timeout: 2) == .completed, let state = bluetooth.manager?.state else {
                return
            }
            // Runs on the manager's queue, after the central's own report of `state`.
            bluetooth.handleBluetoothStateChange(state)
        #endif
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

    // MARK: - What counts

    func testARoundLostToTheRadioIsNotCounted() {
        let loss = TandemPeripheralManager.LinkLoss(disconnectError: CBError(.connectionTimeout))

        XCTAssertEqual(loss, .radio)
        XCTAssertFalse(TandemPeripheralManager.WriteFailure.linkLost(loss).countsAsJpakeFailure)
    }

    func testARoundLostToThePumpEndingTheLinkIsCounted() {
        let loss = TandemPeripheralManager.LinkLoss(disconnectError: CBError(.peripheralDisconnected))

        XCTAssertEqual(loss, .other)
        XCTAssertTrue(TandemPeripheralManager.WriteFailure.linkLost(loss).countsAsJpakeFailure)
    }

    // A connect that ran out of time mid-handshake is cancelled by the driver, with no error.
    func testARoundLostToADisconnectTheDriverAskedForIsCounted() {
        let loss = TandemPeripheralManager.LinkLoss(disconnectError: nil)

        XCTAssertEqual(loss, .other)
        XCTAssertTrue(TandemPeripheralManager.WriteFailure.linkLost(loss).countsAsJpakeFailure)
    }

    func testARoundLostToBluetoothGoingOffIsNotCounted() {
        XCTAssertFalse(TandemPeripheralManager.WriteFailure.linkLost(.bluetooth).countsAsJpakeFailure)
    }

    func testARoundNeverSentIsNotCounted() {
        XCTAssertFalse(TandemPeripheralManager.WriteFailure.notSent.countsAsJpakeFailure)
    }

    func testARoundTheLinkCarriedButThePumpLeftUnansweredIsCounted() {
        XCTAssertTrue(TandemPeripheralManager.WriteFailure.unanswered.countsAsJpakeFailure)
    }

    // MARK: - What it stops

    func testAnAutomaticReconnectIsSkippedOnceTheLimitIsReached() {
        let delegate = attachDelegate()
        reachTheLimit()

        runConnectJob(bluetooth.reconnectAutomatically)

        XCTAssertTrue(manager.state.isConnected, "no connect attempt was made")
        withExtendedLifetime(delegate) {}
    }

    func testAnAutomaticReconnectStillRunsBeforeTheLimit() {
        let delegate = attachDelegate()
        failHandshakes(TandemBluetoothManager.jpakeFailureLimit - 1)

        runConnectJob(bluetooth.reconnectAutomatically)

        XCTAssertFalse(manager.state.isConnected, "a connect attempt was made")
        withExtendedLifetime(delegate) {}
    }

    // MARK: - Whose the manager is

    /// Until a host adopts it, a manager is a setup flow's, which connects as a command when it
    /// needs to; one left pairing on in the background held the pump's one link (#603).
    func testAnAutomaticReconnectIsSkippedUntilAHostAdoptsTheManager() {
        runConnectJob(bluetooth.reconnectAutomatically)

        XCTAssertTrue(manager.state.isConnected, "no connect attempt was made")
    }

    func testAnAutomaticReconnectRunsOnceAHostHasAdoptedTheManager() {
        let delegate = attachDelegate()

        runConnectJob(bluetooth.reconnectAutomatically)

        XCTAssertFalse(manager.state.isConnected, "a connect attempt was made")
        withExtendedLifetime(delegate) {}
    }

    func testAHostCommandStillTriesBeforeAHostAdoptsTheManager() {
        runConnectJob(bluetooth.ensureConnected)

        XCTAssertFalse(manager.state.isConnected, "a connect attempt was made")
    }

    func testBluetoothComingOnDoesNotConnectAManagerNoHostHasAdopted() {
        manager.state.isConnected = true

        bluetooth.handleBluetoothStateChange(.poweredOn)
        // Queued behind the connect the power-on would have started.
        runConnectJob(bluetooth.reconnectAutomatically)

        XCTAssertTrue(manager.state.isConnected, "no connect attempt was made")
    }

    func testAHostCommandStillTriesOnceTheLimitIsReached() {
        reachTheLimit()

        runConnectJob(bluetooth.ensureConnected)

        XCTAssertFalse(manager.state.isConnected, "a connect attempt was made")
    }

    // MARK: - What the host is told

    // The real central also publishes its own state change at a moment no test controls, so these
    // can only assert that the count rises, never that it holds still.
    func testReachingTheLimitIsPublishedToTheHost() {
        let delegate = attachDelegate()
        failHandshakes(TandemBluetoothManager.jpakeFailureLimit - 1)
        manager.delegateQueue.sync {}
        let before = delegate.didUpdateStateCount

        failHandshakes(1)
        manager.delegateQueue.sync {}

        XCTAssertGreaterThan(delegate.didUpdateStateCount, before)
    }

    func testClearingTheLimitIsPublishedToTheHost() {
        let delegate = attachDelegate()
        reachTheLimit()
        manager.delegateQueue.sync {}
        let before = delegate.didUpdateStateCount

        bluetooth.recordJpakeSuccess()
        manager.delegateQueue.sync {}

        XCTAssertGreaterThan(delegate.didUpdateStateCount, before)
    }
}
