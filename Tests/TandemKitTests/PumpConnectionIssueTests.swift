import CoreBluetooth
import LoopKit
@testable import TandemKit
import XCTest

/// The driver's answer to "can we talk to the pump right now?", which every screen reporting a
/// disconnection is built on. Derived from both the phone's radio and the pump link.
@available(macOS 13.0, iOS 14.0, *) final class PumpConnectionIssueTests: XCTestCase {
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

    /// The one combination that is not an issue.
    private func makeConnected() {
        bluetooth.bluetoothState = .poweredOn
        manager.state.isConnected = true
        manager.state.lastReconciliation = Date.now
    }

    // MARK: - What counts as unreachable

    func testNoIssueWhileConnectedAndFreshlySynced() {
        makeConnected()

        XCTAssertNil(manager.connectionIssue)
        XCTAssertNil(manager.sustainedConnectionIssue)
    }

    /// The reported bug: CoreBluetooth invalidates the session without calling
    /// didDisconnectPeripheral, so the radio has to be part of the answer, not only the link.
    func testBluetoothOffIsReportedEvenWhileTheLinkStillLooksUp() {
        makeConnected()
        bluetooth.bluetoothState = .poweredOff

        XCTAssertEqual(manager.connectionIssue, .bluetoothOff)
    }

    func testBluetoothPermissionDeniedIsDistinctFromBluetoothOff() {
        makeConnected()
        bluetooth.bluetoothState = .unauthorized

        XCTAssertEqual(manager.connectionIssue, .bluetoothUnauthorized)
    }

    func testResettingAndUnsupportedRadiosReportAsUnavailable() {
        makeConnected()

        for state in [CBManagerState.resetting, .unsupported] {
            bluetooth.bluetoothState = state
            XCTAssertEqual(manager.connectionIssue, .bluetoothUnavailable, "for \(state.rawValue)")
        }
    }

    /// `.unknown` is the transient before the central starts up, not a fault of its own.
    func testUnknownRadioStateDefersToTheLinkState() {
        makeConnected()
        bluetooth.bluetoothState = .unknown

        XCTAssertNil(manager.connectionIssue)

        manager.state.isConnected = false

        XCTAssertEqual(manager.connectionIssue, .pumpUnreachable)
    }

    func testDroppedLinkOnAWorkingRadioReportsAsPumpUnreachable() {
        makeConnected()
        manager.state.isConnected = false

        XCTAssertEqual(manager.connectionIssue, .pumpUnreachable)
    }

    /// A wedged session is indistinguishable from a healthy one at the link layer; the age of the
    /// last completed sync is the only evidence that it is not.
    func testConnectedButLongUnsyncedReportsAsStale() {
        makeConnected()
        manager.state.lastReconciliation = Date.now
            .addingTimeInterval(-TandemPumpManager.connectionStaleThreshold - 60)

        XCTAssertEqual(manager.connectionIssue, .noRecentSync)
    }

    func testConnectedAndSyncedWithinTheThresholdIsNotStale() {
        makeConnected()
        manager.state.lastReconciliation = Date.now
            .addingTimeInterval(-TandemPumpManager.connectionStaleThreshold + 60)

        XCTAssertNil(manager.connectionIssue)
    }

    /// Both halves together: the sync no longer advances lastSync when the pump answered nothing,
    /// so a link that is up but silent ends up reported as stale instead of as healthy.
    func testAWedgedSessionEndsUpReportedAsStale() {
        makeConnected()
        manager.state.lastReconciliation = Date.now
            .addingTimeInterval(-TandemPumpManager.connectionStaleThreshold - 60)
        // No stubs registered: the link is up and every read returns nil.

        let synced = expectation(description: "syncPumpData completes")
        manager.syncPumpData { _ in synced.fulfill() }
        wait(for: [synced], timeout: 5.0)

        XCTAssertEqual(manager.connectionIssue, .noRecentSync)
    }

    // MARK: - What reaches the home screen

    /// Auto-reconnect clears most drops in seconds; putting each one on the home screen would
    /// train the user to ignore the banner that matters.
    func testARecentlyDroppedLinkIsNotYetWorthTheHomeScreen() {
        makeConnected()
        manager.state.isConnected = false
        manager.state.lastReconciliation = Date.now.addingTimeInterval(-60)

        XCTAssertEqual(manager.connectionIssue, .pumpUnreachable)
        XCTAssertNil(manager.sustainedConnectionIssue)
    }

    func testALinkDownLongEnoughToCostLoopCyclesReachesTheHomeScreen() {
        makeConnected()
        manager.state.isConnected = false
        manager.state.lastReconciliation = Date.now
            .addingTimeInterval(-TandemPumpManager.connectionStaleThreshold - 60)

        XCTAssertEqual(manager.sustainedConnectionIssue, .pumpUnreachable)
    }

    /// A pump that has never synced is being set up, not failing.
    func testANeverSyncedPumpIsNotReportedAsSignalLoss() {
        bluetooth.bluetoothState = .poweredOn
        manager.state.isConnected = false
        manager.state.lastReconciliation = nil

        XCTAssertEqual(manager.connectionIssue, .pumpUnreachable)
        XCTAssertNil(manager.sustainedConnectionIssue)
    }

    /// Radio problems will not clear on their own, so they skip the grace period.
    func testRadioProblemsReachTheHomeScreenImmediately() {
        makeConnected()

        for (state, expected) in [
            (CBManagerState.poweredOff, PumpConnectionIssue.bluetoothOff),
            (.unauthorized, .bluetoothUnauthorized),
            (.unsupported, .bluetoothUnavailable)
        ] {
            bluetooth.bluetoothState = state
            XCTAssertEqual(manager.sustainedConnectionIssue, expected, "for \(state.rawValue)")
        }
    }
}

/// The BLE layer's side of it: `state.isConnected` has to actually go false when the session ends,
/// or everything above reports a pump that is not there.
@available(macOS 13.0, iOS 14.0, *) final class TandemBluetoothManagerLinkStateTests: XCTestCase {
    private var bluetooth: TandemBluetoothManager!
    private var manager: TandemPumpManager!

    override func setUp() {
        super.setUp()
        bluetooth = TandemBluetoothManager()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        manager.state.isConnected = true
    }

    override func tearDown() {
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    /// The case that went unreported. CoreBluetooth tears the session down without calling
    /// didDisconnectPeripheral, so this callback is the driver's only notice.
    func testPoweringBluetoothOffMarksThePumpDisconnected() {
        bluetooth.handleBluetoothStateChange(.poweredOff)

        XCTAssertFalse(manager.state.isConnected)
    }

    func testEveryNonPoweredOnRadioStateMarksThePumpDisconnected() {
        for state in [CBManagerState.poweredOff, .resetting, .unauthorized, .unsupported, .unknown] {
            manager.state.isConnected = true

            bluetooth.handleBluetoothStateChange(state)

            XCTAssertFalse(manager.state.isConnected, "for \(state.rawValue)")
        }
    }

    /// The real central delivers its own state on managerQueue while a test drives this one, and two
    /// overlapping `markLinkDown()`s used to reassign the pump state at once and crash xctest.
    func testConcurrentRadioStateChangesDoNotRace() {
        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            bluetooth.handleBluetoothStateChange(.poweredOff)
        }

        XCTAssertFalse(manager.state.isConnected)
    }

    /// Nothing on screen reads `state` directly, so the change has to be published as well.
    func testLosingBluetoothPublishesAStatusUpdate() {
        let delegate = MockPumpManagerDelegate()
        manager.delegateQueue = DispatchQueue(label: "bluetooth-off-test")
        manager.pumpManagerDelegate = delegate

        let published = expectation(description: "delegate told about the state change")
        published.assertForOverFulfill = false
        delegate.didUpdateStateExpectation = published

        bluetooth.handleBluetoothStateChange(.poweredOff)

        wait(for: [published], timeout: 5.0)
        // The status update follows didUpdateState in the same delegate-queue block, so let it land.
        manager.delegateQueue.sync {}
        XCTAssertFalse(delegate.statusUpdates.isEmpty)
    }
}

// The status highlight is drawn by LoopKitUI, which has no Linux build.
#if canImport(SwiftUI)

/// What the host app's home screen shows — the surface that reported nothing at all when
/// Bluetooth was switched off.
@available(macOS 13.0, iOS 14.0, *) final class PumpConnectionStatusHighlightTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        manager.state.isConnected = true
        manager.state.lastReconciliation = Date.now
    }

    override func tearDown() {
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    private func makeLongDisconnected() {
        manager.state.isConnected = false
        manager.state.lastReconciliation = Date.now
            .addingTimeInterval(-TandemPumpManager.connectionStaleThreshold - 60)
    }

    func testBluetoothOffIsSurfacedOnTheHomeScreen() throws {
        bluetooth.bluetoothState = .poweredOff

        let highlight = try XCTUnwrap(manager.pumpStatusHighlight)

        XCTAssertTrue(
            highlight.localizedMessage.localizedCaseInsensitiveContains("bluetooth"),
            "Got: \(highlight.localizedMessage)"
        )
        XCTAssertEqual(highlight.state, .critical)
    }

    func testASustainedDisconnectionIsSurfacedOnTheHomeScreen() throws {
        makeLongDisconnected()

        let highlight = try XCTUnwrap(manager.pumpStatusHighlight)

        XCTAssertTrue(
            highlight.localizedMessage.localizedCaseInsensitiveContains("disconnected"),
            "Got: \(highlight.localizedMessage)"
        )
    }

    /// The other highlights all describe a pump we have stopped hearing from.
    func testAnUnreachablePumpOutranksTheOtherHighlights() throws {
        manager.state.basalDose = UnfinalizedDose(suspendStartTime: Date.now)
        makeLongDisconnected()

        let highlight = try XCTUnwrap(manager.pumpStatusHighlight)

        XCTAssertTrue(
            highlight.localizedMessage.localizedCaseInsensitiveContains("disconnected"),
            "Got: \(highlight.localizedMessage)"
        )
    }

    /// And the other way: a drop about to clear must not displace a warning about insulin.
    func testAMomentaryDropDoesNotDisplaceATherapyWarning() throws {
        manager.state.basalDose = UnfinalizedDose(suspendStartTime: Date.now)
        manager.state.isConnected = false
        manager.state.lastReconciliation = Date.now.addingTimeInterval(-30)

        let highlight = try XCTUnwrap(manager.pumpStatusHighlight)

        XCTAssertTrue(
            highlight.localizedMessage.localizedCaseInsensitiveContains("suspended"),
            "Got: \(highlight.localizedMessage)"
        )
    }
}

#endif
