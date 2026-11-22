#if TANDEMKIT_VIRTUAL_PUMP
import CoreBluetooth
import Foundation
@testable import TandemKit
import XCTest

/// The driver reconnects on its own after each failed handshake until `jpakeFailureLimit` of them
/// count, so failures that are not counted show as more handshakes than the limit allows.
final class JpakeLinkLossTests: XCTestCase {
    private var server: FakeVirtualPumpServer!
    private var bluetooth: TandemBluetoothManager?
    private var manager: TandemPumpManager?
    private let handshakes = Counter()
    private let connections = Counter()
    private let delegate = MockPumpManagerDelegate()
    private var restoreVirtualPump: () -> Void = {}

    private final class Counter {
        private let lock = NSLock()
        private var value = 0

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        @discardableResult
        func increment() -> Int {
            lock.lock()
            defer { lock.unlock() }
            value += 1
            return value
        }
    }

    private var limit: Int { TandemBluetoothManager.jpakeFailureLimit }

    override func setUpWithError() throws {
        try super.setUpWithError()
        server = FakeVirtualPumpServer()
        try server.start()
    }

    override func tearDown() {
        bluetooth?.deactivate()
        server.stop()
        restoreVirtualPump()
        manager = nil
        bluetooth = nil
        server = nil
        super.tearDown()
    }

    /// Ends every handshake at its first write, with `reason`.
    private func dropAtTheHandshake(reason: String, reaching count: Int, _ reached: XCTestExpectation) {
        server.onWrite = { [handshakes] connection, characteristic, _ in
            guard characteristic == CharacteristicUUID.AUTHORIZATION_CHARACTERISTICS else {
                return
            }
            if handshakes.increment() == count {
                reached.fulfill()
            }
            connection.drop(reason: reason)
        }
    }

    /// A paired pump, so Bluetooth reporting on starts the first connect.
    private func startDriver() {
        let saved = (VirtualPump.endpoint, VirtualPump.scanInterval, VirtualPump.responseTimeout, VirtualPump.connectTimeout)
        restoreVirtualPump = {
            VirtualPump.endpoint = saved.0
            VirtualPump.scanInterval = saved.1
            VirtualPump.responseTimeout = saved.2
            VirtualPump.connectTimeout = saved.3
        }
        VirtualPump.endpoint = server.endpoint
        VirtualPump.scanInterval = 0.2
        VirtualPump.responseTimeout = .seconds(2)
        VirtualPump.connectTimeout = .seconds(10)

        var state = TandemPumpManagerState(rawValue: [:])
        state.pumpState.derivedSecret = Data(repeating: 0x5A, count: 32)
        state.pumpState.pincode = "123456"
        state.pumpState.peripheralUuid = server.peripheralId.uuidString
        let bluetooth = TandemBluetoothManager()
        self.bluetooth = bluetooth
        let manager = TandemPumpManager(state: state, bluetooth: bluetooth)
        // Only a manager a host has adopted reconnects on its own, and hosts adopt one at once.
        manager.pumpManagerDelegate = delegate
        self.manager = manager
    }

    func testThePumpEndingEveryHandshakeStopsTheAutomaticReconnects() {
        let limit = limit
        let reachedTheLimit = expectation(description: "as many handshakes as the limit")
        let pastTheLimit = expectation(description: "a reconnect past the limit")
        pastTheLimit.isInverted = true
        server.onWrite = { [handshakes] connection, characteristic, _ in
            guard characteristic == CharacteristicUUID.AUTHORIZATION_CHARACTERISTICS else {
                return
            }
            switch handshakes.increment() {
            case limit: reachedTheLimit.fulfill()
            // The reconnect after the last failure can start before the setup has counted it.
            case limit + 2: pastTheLimit.fulfill()
            default: break
            }
            connection.drop(reason: "peripheral_shutdown")
        }
        startDriver()

        wait(for: [reachedTheLimit], timeout: 30)
        wait(for: [pastTheLimit], timeout: 3)

        XCTAssertEqual(bluetooth?.isJpakeFailureLimitReached, true)
        XCTAssertEqual(manager?.connectionIssue, .handshakeFailing)
    }

    func testRadioDropsMidHandshakeAreNotCounted() {
        let pastTheLimit = expectation(description: "more handshakes than the limit allows")
        dropAtTheHandshake(reason: CBCentralManager.radioOffReason, reaching: limit + 2, pastTheLimit)
        startDriver()

        wait(for: [pastTheLimit], timeout: 30)

        XCTAssertEqual(bluetooth?.isJpakeFailureLimitReached, false)
        XCTAssertNotEqual(manager?.connectionIssue, .handshakeFailing)
    }

    func testALinkThePumpEndsBeforeTheHandshakeIsNotCounted() {
        let dropped = limit + 1
        server.onAttach = { [connections] _ in connections.increment() }
        server.onSubscribe = { [connections] connection, _ in
            if connections.count <= dropped {
                connection.drop(reason: "peripheral_shutdown")
            }
        }
        // The connection left up reaches its handshake after the dropped ones' setups have ended.
        let handshake = expectation(description: "a handshake on the connection left up")
        handshake.assertForOverFulfill = false
        server.onWrite = { _, characteristic, _ in
            if characteristic == CharacteristicUUID.AUTHORIZATION_CHARACTERISTICS {
                handshake.fulfill()
            }
        }
        startDriver()

        wait(for: [handshake], timeout: 30)

        XCTAssertEqual(bluetooth?.isJpakeFailureLimitReached, false)
        XCTAssertEqual(connections.count, dropped + 1)
    }

    func testAHandshakeWithNoCharacteristicToWriteIsNotCounted() {
        server.omittedCharacteristics = [CharacteristicUUID.AUTHORIZATION_CHARACTERISTICS]
        let limit = limit
        let pastTheLimit = expectation(description: "more connections than the limit allows")
        server.onAttach = { [connections] _ in
            if connections.increment() == limit + 2 {
                pastTheLimit.fulfill()
            }
        }
        startDriver()

        wait(for: [pastTheLimit], timeout: 30)

        XCTAssertEqual(bluetooth?.isJpakeFailureLimitReached, false)
    }
}
#endif
