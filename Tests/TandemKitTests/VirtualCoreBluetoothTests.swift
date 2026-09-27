#if TANDEMKIT_VIRTUAL_PUMP
import CoreBluetooth
import Foundation
@testable import TandemKit
import XCTest
#if canImport(Glibc)
import Glibc
#endif

private final class CentralRecorder: CBCentralManagerDelegate {
    var onStateUpdate: ((CBCentralManager) -> Void)?
    var onDiscover: ((CBPeripheral, [String: Any]) -> Void)?
    var onConnect: ((CBPeripheral) -> Void)?
    var onDisconnect: ((CBPeripheral, Error?) -> Void)?
    var onFailToConnect: ((CBPeripheral, Error?) -> Void)?

    func reset() {
        onStateUpdate = nil
        onDiscover = nil
        onConnect = nil
        onDisconnect = nil
        onFailToConnect = nil
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onStateUpdate?(central)
    }

    func centralManager(
        _: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi _: NSNumber
    ) {
        onDiscover?(peripheral, advertisementData)
    }

    func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        onConnect?(peripheral)
    }

    func centralManager(_: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        onDisconnect?(peripheral, error)
    }

    func centralManager(_: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        onFailToConnect?(peripheral, error)
    }
}

private final class PeripheralRecorder: CBPeripheralDelegate {
    enum Event: Equatable {
        case discoveredServices
        case discoveredCharacteristics(CBUUID)
        case updatedValue(CBUUID, Data?)
        case wroteValue(CBUUID)
        case notificationState(CBUUID)
    }

    private let lock = NSLock()
    private(set) var events: [Event] = []
    var onEvent: ((Event) -> Void)?

    private func record(_ event: Event) {
        lock.lock()
        events.append(event)
        lock.unlock()
        onEvent?(event)
    }

    func peripheral(_: CBPeripheral, didDiscoverServices _: Error?) {
        record(.discoveredServices)
    }

    func peripheral(_: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error _: Error?) {
        record(.discoveredCharacteristics(service.uuid))
    }

    func peripheral(_: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error _: Error?) {
        record(.updatedValue(characteristic.uuid, characteristic.value))
    }

    func peripheral(_: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error _: Error?) {
        record(.wroteValue(characteristic.uuid))
    }

    func peripheral(_: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error _: Error?) {
        record(.notificationState(characteristic.uuid))
    }
}

final class VirtualCoreBluetoothTests: XCTestCase {
    private var server: FakeVirtualPumpServer!
    private var central: CBCentralManager!
    private var recorder: CentralRecorder!
    private let queue = DispatchQueue(label: "VirtualCoreBluetoothTests")

    override func setUpWithError() throws {
        try super.setUpWithError()
        server = FakeVirtualPumpServer()
        try server.start()
        recorder = CentralRecorder()
        central = CBCentralManager(
            delegate: recorder,
            queue: queue,
            endpoint: server.endpoint,
            scanInterval: 0.2
        )
    }

    override func tearDown() {
        // The teardown disconnect below must not land in a test's already-fulfilled expectation.
        recorder.reset()
        central.stopScan()
        for peripheral in central.retrieveConnectedPeripherals(withServices: []) {
            central.cancelPeripheralConnection(peripheral)
        }
        server.stop()
        central = nil
        server = nil
        recorder = nil
        super.tearDown()
    }

    private func connectPeripheral() throws -> CBPeripheral {
        let peripheral = try XCTUnwrap(central.retrievePeripherals(withIdentifiers: [server.peripheralId]).first)
        let connected = expectation(description: "didConnect")
        recorder.onConnect = { _ in connected.fulfill() }
        central.connect(peripheral)
        wait(for: [connected], timeout: 5)
        return peripheral
    }

    /// Discovers both services and all their characteristics, the way TandemPeripheralManager does.
    private func discover(_ peripheral: CBPeripheral) throws {
        let events = PeripheralRecorder()
        peripheral.delegate = events
        let servicesFound = expectation(description: "didDiscoverServices")
        events.onEvent = { if $0 == .discoveredServices { servicesFound.fulfill() } }
        peripheral.discoverServices(ServiceUUID.all)
        wait(for: [servicesFound], timeout: 2)

        let characteristicsFound = expectation(description: "didDiscoverCharacteristicsFor")
        characteristicsFound.expectedFulfillmentCount = 2
        events.onEvent = { if case .discoveredCharacteristics = $0 { characteristicsFound.fulfill() } }
        for service in try XCTUnwrap(peripheral.services) {
            peripheral.discoverCharacteristics(nil, for: service)
        }
        wait(for: [characteristicsFound], timeout: 2)
        peripheral.delegate = nil
    }

    private func characteristic(_ uuid: CBUUID, of peripheral: CBPeripheral) throws -> CBCharacteristic {
        try XCTUnwrap(peripheral.services?.lazy.compactMap { $0.characteristics?.first { $0.uuid == uuid } }.first)
    }

    func testEndpointParsing() {
        XCTAssertEqual(SocketPumpEndpoint("127.0.0.1:8081"), SocketPumpEndpoint(host: "127.0.0.1", port: 8081))
        XCTAssertEqual(SocketPumpEndpoint("pump.local:1"), SocketPumpEndpoint(host: "pump.local", port: 1))
        XCTAssertEqual(SocketPumpEndpoint("8081"), SocketPumpEndpoint(host: "127.0.0.1", port: 8081))
        XCTAssertNil(SocketPumpEndpoint(":8081"))
        XCTAssertNil(SocketPumpEndpoint("host:"))
        XCTAssertNil(SocketPumpEndpoint("host:notaport"))
    }

    func testCoreBluetoothInitializerUsesTheConfiguredEndpoint() {
        let saved = VirtualPump.endpoint
        defer { VirtualPump.endpoint = saved }

        VirtualPump.endpoint = server.endpoint
        XCTAssertEqual(CBCentralManager(delegate: nil, queue: nil).endpoint, server.endpoint)

        VirtualPump.endpoint = nil
        XCTAssertEqual(CBCentralManager(delegate: nil, queue: nil).state, .unsupported)
    }

    func testStateIsDeliveredAsynchronouslyAfterInit() {
        let delegate = CentralRecorder()
        let announced = expectation(description: "centralManagerDidUpdateState")
        var created: CBCentralManager?
        delegate.onStateUpdate = { central in
            XCTAssertTrue(central === created, "delivered after init returned")
            XCTAssertEqual(central.state, .poweredOn)
            announced.fulfill()
        }
        let queue = DispatchQueue(label: "testStateIsDeliveredAsynchronouslyAfterInit")
        queue.sync {
            created = CBCentralManager(delegate: delegate, queue: queue, endpoint: server.endpoint, scanInterval: 1)
        }
        wait(for: [announced], timeout: 2)
    }

    func testScanReportsHelloAsAnAdvertisement() {
        let discovered = expectation(description: "didDiscover")
        discovered.assertForOverFulfill = false
        var seen: (CBPeripheral, [String: Any])?
        recorder.onDiscover = { peripheral, advertisement in
            seen = (peripheral, advertisement)
            discovered.fulfill()
        }

        central.scanForPeripherals(
            withServices: [ServiceUUID.PUMP_SERVICE],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        XCTAssertTrue(central.isScanning)
        wait(for: [discovered], timeout: 5)
        central.stopScan()
        XCTAssertFalse(central.isScanning)

        let (peripheral, advertisement) = seen!
        XCTAssertEqual(peripheral.identifier, server.peripheralId)
        XCTAssertEqual(peripheral.name, server.name)
        XCTAssertEqual(advertisement[CBAdvertisementDataManufacturerDataKey] as? Data, server.manufacturerData)
        XCTAssertEqual(peripheral.state, .disconnected)
        XCTAssertEqual(server.attachCount, 0, "a scan probe reads hello only, it never attaches")
    }

    func testScanRepeatsWhileScanningAndStopsOnStopScan() {
        let twice = expectation(description: "two advertisements")
        twice.expectedFulfillmentCount = 2
        twice.assertForOverFulfill = false
        recorder.onDiscover = { _, _ in twice.fulfill() }

        central.scanForPeripherals(
            withServices: [ServiceUUID.PUMP_SERVICE],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        wait(for: [twice], timeout: 5)
        central.stopScan()

        let settled = expectation(description: "no more probes")
        settled.isInverted = true
        recorder.onDiscover = { _, _ in settled.fulfill() }
        wait(for: [settled], timeout: 0.6)
    }

    func testScanWithoutAllowDuplicatesReportsThePumpOnce() {
        var reports = 0
        recorder.onDiscover = { _, _ in reports += 1 }

        central.scanForPeripherals(withServices: [ServiceUUID.PUMP_SERVICE])
        let probing = expectation(description: "several probes")
        probing.isInverted = true
        wait(for: [probing], timeout: 1)
        central.stopScan()

        XCTAssertGreaterThanOrEqual(server.helloCount, 2, "probes kept running; only the report was suppressed")
        XCTAssertEqual(queue.sync { reports }, 1)
    }

    func testScanForAServiceThePumpDoesNotOfferReportsNothing() {
        let nothing = expectation(description: "no advertisement")
        nothing.isInverted = true
        recorder.onDiscover = { _, _ in nothing.fulfill() }

        central.scanForPeripherals(
            withServices: [CBUUID(string: "0000FFFF-0000-1000-8000-00805F9B34FB")],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        wait(for: [nothing], timeout: 0.6)
    }

    func testSocketLinkWriteToAClosedPeerThrowsInsteadOfRaisingSigpipe() {
        var fds: [Int32] = [0, 0]
        #if canImport(Glibc)
        XCTAssertEqual(socketpair(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0, &fds), 0)
        let link = SocketLink(fd: fds[0])
        Glibc.close(fds[1])
        #else
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds), 0)
        let link = SocketLink(fd: fds[0])
        Darwin.close(fds[1])
        #endif

        XCTAssertThrowsError(try link.send(["type": "hello"]))
        link.close()
    }

    func testScannedPeripheralIsTheSameObjectAsRetrievedAndConnected() throws {
        let discovered = expectation(description: "didDiscover")
        discovered.assertForOverFulfill = false
        var scanned: CBPeripheral?
        recorder.onDiscover = { peripheral, _ in
            scanned = peripheral
            discovered.fulfill()
        }
        central.scanForPeripherals(withServices: [ServiceUUID.PUMP_SERVICE])
        wait(for: [discovered], timeout: 5)
        central.stopScan()

        let retrieved = try XCTUnwrap(central.retrievePeripherals(withIdentifiers: [server.peripheralId]).first)
        XCTAssertTrue(retrieved === scanned!)

        let connected = try connectPeripheral()
        XCTAssertTrue(connected === scanned!)
        XCTAssertTrue(try XCTUnwrap(central.retrieveConnectedPeripherals(withServices: [ServiceUUID.PUMP_SERVICE])
                .first) === scanned!)
    }

    func testServicesAppearOnlyThroughDiscovery() throws {
        let peripheral = try connectPeripheral()
        XCTAssertEqual(peripheral.state, .connected)
        XCTAssertEqual(server.attachCount, 1)
        XCTAssertNil(peripheral.services, "CoreBluetooth has no services before discoverServices")

        try discover(peripheral)

        XCTAssertEqual(peripheral.services?.map(\.uuid), [ServiceUUID.PUMP_SERVICE, ServiceUUID.DIS_SERVICE])
        let status = try characteristic(CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS, of: peripheral)
        XCTAssertEqual(status.service?.uuid, ServiceUUID.PUMP_SERVICE)
        XCTAssertTrue(status.service?.peripheral === peripheral)
        let model = try characteristic(CharacteristicUUID.DIS_MODEL_NUMBER, of: peripheral)
        XCTAssertEqual(model.service?.uuid, ServiceUUID.DIS_SERVICE)
    }

    func testRediscoveryKeepsTheSameObjects() throws {
        let peripheral = try connectPeripheral()
        try discover(peripheral)
        let first = try characteristic(CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS, of: peripheral)

        try discover(peripheral)

        XCTAssertTrue(try characteristic(CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS, of: peripheral) === first)
    }

    func testDiscoveryCallbacksArriveAsynchronously() throws {
        let peripheral = try connectPeripheral()
        let events = PeripheralRecorder()
        peripheral.delegate = events

        let done = expectation(description: "discovery")
        // A delegate callback never runs synchronously on the requesting thread (here, main).
        // Checking `events.isEmpty` after the request instead would race the central's queue.
        events.onEvent = { _ in
            XCTAssertFalse(Thread.isMainThread, "callbacks must not run synchronously from the request")
            done.fulfill()
        }
        peripheral.discoverServices(ServiceUUID.all)
        wait(for: [done], timeout: 2)
        XCTAssertEqual(events.events, [.discoveredServices])
    }

    func testConnectToAnUnknownIdentifierFails() {
        let stranger = central.retrievePeripherals(withIdentifiers: [UUID()]).first!
        let failed = expectation(description: "didFailToConnect")
        recorder.onFailToConnect = { peripheral, error in
            XCTAssertTrue(peripheral === stranger)
            XCTAssertNotNil(error)
            failed.fulfill()
        }
        central.connect(stranger)
        wait(for: [failed], timeout: 5)
        XCTAssertEqual(stranger.state, .disconnected)
        XCTAssertEqual(server.attachCount, 0)
    }

    func testWriteAckArrivesBeforeTheResponseNotification() throws {
        let peripheral = try connectPeripheral()
        try discover(peripheral)
        let events = PeripheralRecorder()
        peripheral.delegate = events
        let status = try characteristic(CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS, of: peripheral)

        let subscribed = expectation(description: "subscribe_ack")
        events.onEvent = { if $0 == .notificationState(status.uuid) { subscribed.fulfill() } }
        peripheral.setNotifyValue(true, for: status)
        wait(for: [subscribed], timeout: 2)

        let response = Data([0x00, 0x01, 0x21, 0x01, 0x04, 0xAA, 0xBB])
        server.onWrite = { connection, characteristic, _ in
            connection.notify(characteristic, response)
        }
        let answered = expectation(description: "response notification")
        events.onEvent = { if case .updatedValue = $0 { answered.fulfill() } }
        let request = Data([0x00, 0x01, 0x20, 0x01, 0x00, 0x12, 0x34])
        peripheral.writeValue(request, for: status, type: .withResponse)
        wait(for: [answered], timeout: 2)

        XCTAssertEqual(server.writes.map(\.value), [request])
        XCTAssertEqual(server.writes.first?.characteristic, status.uuid)
        XCTAssertEqual(
            events.events.dropFirst(),
            [.wroteValue(status.uuid), .updatedValue(status.uuid, response)],
            "write_ack must be delivered as didWriteValue before the notify becomes didUpdateValue"
        )
        XCTAssertEqual(status.value, response)
    }

    func testNotificationsRouteToDidUpdateValueOnlyWhileSubscribed() throws {
        let peripheral = try connectPeripheral()
        try discover(peripheral)
        let events = PeripheralRecorder()
        peripheral.delegate = events
        let status = try characteristic(CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS, of: peripheral)
        let control = CharacteristicUUID.CONTROL_CHARACTERISTICS
        let connection = try XCTUnwrap(server.latestAttachedConnection)

        XCTAssertFalse(connection.notify(status.uuid, Data([1])), "unsubscribed: the pump drops it")

        let subscribed = expectation(description: "subscribe_ack")
        events.onEvent = { if $0 == .notificationState(status.uuid) { subscribed.fulfill() } }
        peripheral.setNotifyValue(true, for: status)
        wait(for: [subscribed], timeout: 2)

        let delivered = expectation(description: "notify")
        events.onEvent = { if case .updatedValue = $0 { delivered.fulfill() } }
        XCTAssertTrue(connection.notify(status.uuid, Data([2, 3])))
        XCTAssertFalse(connection.notify(control, Data([9])), "a different, unsubscribed characteristic")
        wait(for: [delivered], timeout: 2)

        XCTAssertEqual(events.events, [.notificationState(status.uuid), .updatedValue(status.uuid, Data([2, 3]))])
        XCTAssertEqual(connection.droppedNotifies, [status.uuid, control])
    }

    func testReadValueSetsTheValueBeforeTheCallback() throws {
        let peripheral = try connectPeripheral()
        try discover(peripheral)
        let events = PeripheralRecorder()
        peripheral.delegate = events
        let model = try characteristic(CharacteristicUUID.DIS_MODEL_NUMBER, of: peripheral)

        let read = expectation(description: "read_result")
        events.onEvent = { if case .updatedValue = $0 { read.fulfill() } }
        peripheral.readValue(for: model)
        wait(for: [read], timeout: 2)

        XCTAssertEqual(events.events, [.updatedValue(model.uuid, Data("Mobi".utf8))])
    }

    func testPumpInitiatedDisconnectReachesTheCentralDelegate() throws {
        let peripheral = try connectPeripheral()
        try discover(peripheral)

        let dropped = expectation(description: "didDisconnect")
        var reported: Error?
        recorder.onDisconnect = { disconnected, error in
            XCTAssertTrue(disconnected === peripheral)
            XCTAssertEqual(disconnected.state, .disconnected, "state changes before the callback")
            reported = error
            dropped.fulfill()
        }
        try XCTUnwrap(server.latestAttachedConnection).drop(reason: "fault_injection")
        wait(for: [dropped], timeout: 5)

        XCTAssertEqual(reported as? SocketPumpError, .pumpDisconnected(reason: "fault_injection"))
        XCTAssertNil(peripheral.services, "services must be rediscovered after reconnecting")
        XCTAssertTrue(central.retrieveConnectedPeripherals(withServices: [ServiceUUID.PUMP_SERVICE]).isEmpty)
    }

    func testCancelPeripheralConnectionReportsACleanDisconnect() throws {
        let peripheral = try connectPeripheral()

        let dropped = expectation(description: "didDisconnect")
        var reported: Error? = SocketPumpError.timedOut
        recorder.onDisconnect = { _, error in
            reported = error
            dropped.fulfill()
        }
        central.cancelPeripheralConnection(peripheral)
        wait(for: [dropped], timeout: 5)

        XCTAssertNil(reported)
        XCTAssertEqual(peripheral.state, .disconnected)
    }

    func testReconnectAfterDisconnectReusesThePeripheral() throws {
        let peripheral = try connectPeripheral()

        let dropped = expectation(description: "didDisconnect")
        recorder.onDisconnect = { _, _ in dropped.fulfill() }
        try XCTUnwrap(server.latestAttachedConnection).drop(reason: "restart")
        wait(for: [dropped], timeout: 5)

        let again = try connectPeripheral()
        XCTAssertTrue(again === peripheral)
        XCTAssertEqual(peripheral.state, .connected)
        XCTAssertEqual(server.attachCount, 2)
    }

    /// The real driver on top of the socket: TandemPeripheralManager packetizes an unsigned request,
    /// the pump answers with a packetized response, and the parsed message comes back to the caller.
    func testPeripheralManagerRoundTripsAnApiVersionRequest() throws {
        let peripheral = try connectPeripheral()
        try discover(peripheral)
        let peripheralManager = makePeripheralManager(for: peripheral)

        var requestSeen: Data?
        server.onWrite = { connection, characteristic, value in
            requestSeen = value
            // [packetsRemaining, txId, opCode, txId, cargoLength, ...]: echo the txId so the
            // response pairs with the request the way the pump does.
            let txId = value[1]
            let response = ApiVersionResponse(majorVersion: 3, minorVersion: 7)
            for packet in Packetize.parse(message: response, authenticationKey: nil, txId: txId, timeSinceReset: nil) {
                connection.notify(characteristic, packet.build())
            }
        }

        let answered = expectation(description: "ApiVersionResponse")
        var received: ApiVersionResponse?
        DispatchQueue.global().async {
            peripheralManager.startNotify(
                service: ServiceUUID.PUMP_SERVICE,
                characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
            )
            received = peripheralManager.write(ApiVersionRequest())
            answered.fulfill()
        }
        wait(for: [answered], timeout: 10)

        XCTAssertEqual(received?.majorVersion, 3)
        XCTAssertEqual(received?.minorVersion, 7)
        XCTAssertEqual(server.writes.count, 1)
        XCTAssertEqual(server.writes.first?.characteristic, CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS)
        XCTAssertEqual(requestSeen?[2], ApiVersionRequest.props.opCode)
        XCTAssertEqual(try XCTUnwrap(server.latestAttachedConnection).droppedNotifies, [])
    }

    /// A response longer than one 18-byte chunk arrives as several notifications, back to back;
    /// only the first carries the opcode at byte 2, the rest carry cargo there, and the last one can
    /// be as short as three bytes. The driver used to match every notification against the expected
    /// opcode (dropping continuations as unhandled) and to reject three-byte packets, so the
    /// write timed out. Jpake4KeyConfirmationResponse (50 cargo bytes -> 20+20+20+3) hits both.
    func testPeripheralManagerReassemblesAMultiPacketResponse() throws {
        let peripheral = try connectPeripheral()
        try discover(peripheral)
        let peripheralManager = makePeripheralManager(for: peripheral)
        let nonce = Data([0xE6, 0x8B, 0x38, 0xDA, 0x41, 0x3F, 0xC8, 0x68])
        let digest = Data((0 ..< 32).map { UInt8($0) })

        var fragments: [Data] = []
        server.onWrite = { connection, characteristic, value in
            // The 50-byte request is itself four writes; answer the last one.
            guard value[0] == 0 else { return }
            let response = Jpake4KeyConfirmationResponse(
                appInstanceId: 0,
                nonce: nonce,
                reserved: Data(count: 8),
                hashDigest: digest
            )
            for packet in Packetize.parse(message: response, authenticationKey: nil, txId: value[1], timeSinceReset: nil) {
                fragments.append(packet.build())
                connection.notify(characteristic, packet.build())
            }
        }

        let answered = expectation(description: "Jpake4KeyConfirmationResponse")
        var received: Jpake4KeyConfirmationResponse?
        DispatchQueue.global().async {
            peripheralManager.startNotify(
                service: ServiceUUID.PUMP_SERVICE,
                characteristic: CharacteristicUUID.AUTHORIZATION_CHARACTERISTICS
            )
            received = peripheralManager.write(Jpake4KeyConfirmationRequest(
                appInstanceId: 0,
                nonce: nonce,
                reserved: Data(count: 8),
                hashDigest: digest
            ))
            answered.fulfill()
        }
        wait(for: [answered], timeout: 10)

        XCTAssertEqual(fragments.map(\.count), [20, 20, 20, 3], "the fixture must fragment the way the pump does")
        XCTAssertEqual(fragments[0][2], Jpake4KeyConfirmationResponse.props.opCode)
        XCTAssertNotEqual(fragments[1][2], Jpake4KeyConfirmationResponse.props.opCode, "a continuation packet carries cargo at byte 2")
        XCTAssertEqual(received?.hashDigest, digest)
    }

    func testAnErrorResponseNamingThePendingRequestFailsTheWriteAtOnce() throws {
        let peripheral = try connectPeripheral()
        try discover(peripheral)
        let peripheralManager = makePeripheralManager(for: peripheral)
        server.onWrite = { connection, _, value in
            connection.notify(
                CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS,
                Self.errorResponse(txId: value[1], requestCodeId: ApiVersionRequest.props.opCode)
            )
        }

        let result = writeApiVersion(with: peripheralManager)

        XCTAssertNil(result.response)
        XCTAssertLessThan(result.seconds, 5, "the production response timeout is 30 s")
    }

    func testAnErrorResponseForAnotherRequestLeavesTheWritePending() throws {
        let saved = VirtualPump.responseTimeout
        VirtualPump.responseTimeout = .seconds(1)
        defer { VirtualPump.responseTimeout = saved }
        let peripheral = try connectPeripheral()
        try discover(peripheral)
        let peripheralManager = makePeripheralManager(for: peripheral)
        server.onWrite = { connection, _, value in
            connection.notify(
                CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS,
                Self.errorResponse(txId: value[1], requestCodeId: ApiVersionRequest.props.opCode &+ 2)
            )
        }

        let result = writeApiVersion(with: peripheralManager)

        XCTAssertNil(result.response)
        XCTAssertGreaterThanOrEqual(result.seconds, 0.9, "only the response timeout ends it")
    }

    func testAnErrorResponseArrivingMidResponseLeavesTheResponseStanding() throws {
        let peripheral = try connectPeripheral()
        try discover(peripheral)
        let peripheralManager = makePeripheralManager(for: peripheral)
        let nonce = Data([0xE6, 0x8B, 0x38, 0xDA, 0x41, 0x3F, 0xC8, 0x68])
        let digest = Data((0 ..< 32).map { UInt8($0) })

        server.onWrite = { connection, characteristic, value in
            guard value[0] == 0 else { return }
            let response = Jpake4KeyConfirmationResponse(
                appInstanceId: 0,
                nonce: nonce,
                reserved: Data(count: 8),
                hashDigest: digest
            )
            let packets = Packetize.parse(message: response, authenticationKey: nil, txId: value[1], timeSinceReset: nil)
            for (index, packet) in packets.enumerated() {
                connection.notify(characteristic, packet.build())
                if index == 0 {
                    connection.notify(
                        CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS,
                        Self.errorResponse(txId: value[1], requestCodeId: Jpake4KeyConfirmationRequest.props.opCode)
                    )
                }
            }
        }

        let answered = expectation(description: "Jpake4KeyConfirmationResponse")
        var received: Jpake4KeyConfirmationResponse?
        DispatchQueue.global().async {
            for characteristic in [CharacteristicUUID.AUTHORIZATION_CHARACTERISTICS, CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS] {
                peripheralManager.startNotify(service: ServiceUUID.PUMP_SERVICE, characteristic: characteristic)
            }
            received = peripheralManager.write(Jpake4KeyConfirmationRequest(
                appInstanceId: 0,
                nonce: nonce,
                reserved: Data(count: 8),
                hashDigest: digest
            ))
            answered.fulfill()
        }
        wait(for: [answered], timeout: 10)

        XCTAssertEqual(received?.hashDigest, digest)
    }

    /// faketandem's single-fragment, unsigned ErrorResponse (pkg/protocol BuildErrorResponse).
    private static func errorResponse(txId: UInt8, requestCodeId: UInt8) -> Data {
        let body = Data([ErrorResponse.props.opCode, txId, 2, requestCodeId, 3])
        return Data([0, txId]) + body + body.crc16()
    }

    private func writeApiVersion(with peripheralManager: TandemPeripheralManager) -> (response: ApiVersionResponse?, seconds: TimeInterval) {
        let answered = expectation(description: "write returned")
        var response: ApiVersionResponse?
        var seconds: TimeInterval = 0
        DispatchQueue.global().async {
            peripheralManager.startNotify(
                service: ServiceUUID.PUMP_SERVICE,
                characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
            )
            let started = Date()
            response = peripheralManager.write(ApiVersionRequest())
            seconds = Date().timeIntervalSince(started)
            answered.fulfill()
        }
        wait(for: [answered], timeout: 10)
        return (response, seconds)
    }

    private func makePeripheralManager(for peripheral: CBPeripheral) -> TandemPeripheralManager {
        let pumpManager = TandemPumpManager(
            state: TandemPumpManagerState(rawValue: [:]),
            bluetooth: StubPumpBluetooth()
        )
        return TandemPeripheralManager(TandemBluetoothManager(), peripheral, pumpManager) { _ in }
    }
}
#endif
