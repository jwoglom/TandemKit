import CoreBluetooth
import Foundation
@testable import TandemKit
import XCTest

private final class CentralRecorder: PumpCentralDelegate {
    var onStateUpdate: ((PumpCentral) -> Void)?
    var onDiscover: ((PumpPeripheral, [String: Any]) -> Void)?
    var onConnect: ((PumpPeripheral) -> Void)?
    var onDisconnect: ((PumpPeripheral, Error?) -> Void)?
    var onFailToConnect: ((PumpPeripheral, Error?) -> Void)?

    func reset() {
        onStateUpdate = nil
        onDiscover = nil
        onConnect = nil
        onDisconnect = nil
        onFailToConnect = nil
    }

    func centralDidUpdateState(_ central: PumpCentral) {
        onStateUpdate?(central)
    }

    func central(
        _: PumpCentral,
        didDiscover peripheral: PumpPeripheral,
        advertisementData: [String: Any],
        rssi _: NSNumber
    ) {
        onDiscover?(peripheral, advertisementData)
    }

    func central(_: PumpCentral, didConnect peripheral: PumpPeripheral) {
        onConnect?(peripheral)
    }

    func central(_: PumpCentral, didDisconnect peripheral: PumpPeripheral, error: Error?) {
        onDisconnect?(peripheral, error)
    }

    func central(_: PumpCentral, didFailToConnect peripheral: PumpPeripheral, error: Error?) {
        onFailToConnect?(peripheral, error)
    }
}

private final class PeripheralRecorder: PumpPeripheralDelegate {
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

    func peripheral(_: PumpPeripheral, didDiscoverServices _: Error?) {
        record(.discoveredServices)
    }

    func peripheral(_: PumpPeripheral, didDiscoverCharacteristicsFor service: CBUUID, error _: Error?) {
        record(.discoveredCharacteristics(service))
    }

    func peripheral(_: PumpPeripheral, didUpdateValueFor characteristic: CBUUID, value: Data?, error _: Error?) {
        record(.updatedValue(characteristic, value))
    }

    func peripheral(_: PumpPeripheral, didWriteValueFor characteristic: CBUUID, error _: Error?) {
        record(.wroteValue(characteristic))
    }

    func peripheral(_: PumpPeripheral, didUpdateNotificationStateFor characteristic: CBUUID, error _: Error?) {
        record(.notificationState(characteristic))
    }
}

/// A central that never powers on, for a TandemBluetoothManager that must stay out of the way.
private final class InertCentral: PumpCentral {
    var state: CBManagerState { .poweredOff }
    var isScanning: Bool { false }
    weak var delegate: PumpCentralDelegate?
    func scanForPeripherals(withServices _: [CBUUID], allowDuplicates _: Bool) {}
    func stopScan() {}
    func connect(_: PumpPeripheral) {}
    func cancelPeripheralConnection(_: PumpPeripheral) {}
    func retrievePeripherals(withIdentifiers _: [UUID]) -> [PumpPeripheral] { [] }
    func retrieveConnectedPeripherals(withServices _: [CBUUID]) -> [PumpPeripheral] { [] }
}

final class SocketPumpTransportTests: XCTestCase {
    private var server: FakeVirtualPumpServer!
    private var central: SocketPumpCentral!
    private var recorder: CentralRecorder!

    override func setUpWithError() throws {
        try super.setUpWithError()
        server = FakeVirtualPumpServer()
        try server.start()
        central = SocketPumpCentral(endpoint: server.endpoint, scanInterval: 0.2)
        recorder = CentralRecorder()
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

    private func connectPeripheral() throws -> PumpPeripheral {
        let peripheral = try XCTUnwrap(central.retrievePeripherals(withIdentifiers: [server.peripheralId]).first)
        let connected = expectation(description: "didConnect")
        recorder.onConnect = { _ in connected.fulfill() }
        central.connect(peripheral)
        wait(for: [connected], timeout: 5)
        return peripheral
    }

    func testEndpointParsing() {
        XCTAssertEqual(SocketPumpEndpoint("127.0.0.1:8081"), SocketPumpEndpoint(host: "127.0.0.1", port: 8081))
        XCTAssertEqual(SocketPumpEndpoint("pump.local:1"), SocketPumpEndpoint(host: "pump.local", port: 1))
        XCTAssertEqual(SocketPumpEndpoint("8081"), SocketPumpEndpoint(host: "127.0.0.1", port: 8081))
        XCTAssertNil(SocketPumpEndpoint(":8081"))
        XCTAssertNil(SocketPumpEndpoint("host:"))
        XCTAssertNil(SocketPumpEndpoint("host:notaport"))
    }

    func testFactoryPicksTheSocketCentralFromTheEnvironment() {
        let env = [PumpCentralFactory.virtualPumpEnvironmentVariable: "127.0.0.1:\(server.port)"]
        let socket = PumpCentralFactory.makeDefault(environment: env) as? SocketPumpCentral
        XCTAssertEqual(socket?.endpoint, server.endpoint)
    }

    func testStateIsAnnouncedAfterTheDelegateIsSet() {
        let announced = expectation(description: "centralDidUpdateState")
        recorder.onStateUpdate = { central in
            XCTAssertEqual(central.state, .poweredOn)
            announced.fulfill()
        }
        central.delegate = recorder
        wait(for: [announced], timeout: 2)
    }

    func testScanReportsHelloAsAnAdvertisement() {
        central.delegate = recorder
        let discovered = expectation(description: "didDiscover")
        discovered.assertForOverFulfill = false
        var seen: (PumpPeripheral, [String: Any])?
        recorder.onDiscover = { peripheral, advertisement in
            seen = (peripheral, advertisement)
            discovered.fulfill()
        }

        central.scanForPeripherals(withServices: [ServiceUUID.PUMP_SERVICE], allowDuplicates: true)
        XCTAssertTrue(central.isScanning)
        wait(for: [discovered], timeout: 5)
        central.stopScan()
        XCTAssertFalse(central.isScanning)

        let (peripheral, advertisement) = seen!
        XCTAssertEqual(peripheral.identifier, server.peripheralId)
        XCTAssertEqual(peripheral.name, server.name)
        XCTAssertEqual(advertisement[CBAdvertisementDataManufacturerDataKey] as? Data, server.manufacturerData)
        XCTAssertFalse(peripheral.isConnected)
        XCTAssertEqual(server.attachCount, 0, "a scan probe reads hello only, it never attaches")
    }

    func testScanRepeatsWhileScanningAndStopsOnStopScan() {
        central.delegate = recorder
        let twice = expectation(description: "two advertisements")
        twice.expectedFulfillmentCount = 2
        twice.assertForOverFulfill = false
        recorder.onDiscover = { _, _ in twice.fulfill() }

        central.scanForPeripherals(withServices: [ServiceUUID.PUMP_SERVICE], allowDuplicates: true)
        wait(for: [twice], timeout: 5)
        central.stopScan()

        let settled = expectation(description: "no more probes")
        settled.isInverted = true
        recorder.onDiscover = { _, _ in settled.fulfill() }
        wait(for: [settled], timeout: 0.6)
    }

    func testScannedPeripheralIsTheSameObjectAsRetrievedAndConnected() throws {
        central.delegate = recorder
        let discovered = expectation(description: "didDiscover")
        discovered.assertForOverFulfill = false
        var scanned: PumpPeripheral?
        recorder.onDiscover = { peripheral, _ in
            scanned = peripheral
            discovered.fulfill()
        }
        central.scanForPeripherals(withServices: [ServiceUUID.PUMP_SERVICE], allowDuplicates: true)
        wait(for: [discovered], timeout: 5)
        central.stopScan()

        let retrieved = try XCTUnwrap(central.retrievePeripherals(withIdentifiers: [server.peripheralId]).first)
        XCTAssertTrue(retrieved === scanned!)

        let connected = try connectPeripheral()
        XCTAssertTrue(connected === scanned!)
        XCTAssertTrue(try XCTUnwrap(central.retrieveConnectedPeripherals(withServices: [ServiceUUID.PUMP_SERVICE])
                .first) === scanned!)
    }

    func testConnectAttachesAndPopulatesServices() throws {
        central.delegate = recorder
        let peripheral = try connectPeripheral()

        XCTAssertTrue(peripheral.isConnected)
        XCTAssertEqual(server.attachCount, 1)
        XCTAssertEqual(peripheral.name, server.name)
        XCTAssertEqual(peripheral.discoveredServices, [ServiceUUID.PUMP_SERVICE, ServiceUUID.DIS_SERVICE])
        XCTAssertTrue(peripheral.hasCharacteristic(
            CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS,
            in: ServiceUUID.PUMP_SERVICE
        ))
        XCTAssertTrue(peripheral.hasCharacteristic(CharacteristicUUID.DIS_MODEL_NUMBER, in: ServiceUUID.DIS_SERVICE))
        XCTAssertFalse(peripheral.hasCharacteristic(CharacteristicUUID.DIS_MODEL_NUMBER, in: ServiceUUID.PUMP_SERVICE))
    }

    func testDiscoveryCallbacksArriveAsynchronously() throws {
        central.delegate = recorder
        let peripheral = try connectPeripheral()
        let events = PeripheralRecorder()
        peripheral.delegate = events

        let done = expectation(description: "discovery")
        done.expectedFulfillmentCount = 2
        events.onEvent = { _ in done.fulfill() }
        peripheral.discoverServices(ServiceUUID.all)
        peripheral.discoverCharacteristics(CharacteristicUUID.allPumpCharacteristics, for: ServiceUUID.PUMP_SERVICE)
        XCTAssertTrue(events.events.isEmpty, "callbacks must not run synchronously from the request")
        wait(for: [done], timeout: 2)
        XCTAssertEqual(events.events, [.discoveredServices, .discoveredCharacteristics(ServiceUUID.PUMP_SERVICE)])
    }

    func testConnectToAnUnknownIdentifierFails() {
        central.delegate = recorder
        let stranger = central.retrievePeripherals(withIdentifiers: [UUID()]).first!
        let failed = expectation(description: "didFailToConnect")
        recorder.onFailToConnect = { peripheral, error in
            XCTAssertTrue(peripheral === stranger)
            XCTAssertNotNil(error)
            failed.fulfill()
        }
        central.connect(stranger)
        wait(for: [failed], timeout: 5)
        XCTAssertFalse(stranger.isConnected)
        XCTAssertEqual(server.attachCount, 0)
    }

    func testWriteAckArrivesBeforeTheResponseNotification() throws {
        central.delegate = recorder
        let peripheral = try connectPeripheral()
        let events = PeripheralRecorder()
        peripheral.delegate = events
        let status = CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS

        let subscribed = expectation(description: "subscribe_ack")
        events.onEvent = { if $0 == .notificationState(status) { subscribed.fulfill() } }
        peripheral.setNotifyValue(true, for: status, in: ServiceUUID.PUMP_SERVICE)
        wait(for: [subscribed], timeout: 2)

        let response = Data([0x00, 0x01, 0x21, 0x01, 0x04, 0xAA, 0xBB])
        server.onWrite = { connection, characteristic, _ in
            connection.notify(characteristic, response)
        }
        let answered = expectation(description: "response notification")
        events.onEvent = { if case .updatedValue = $0 { answered.fulfill() } }
        let request = Data([0x00, 0x01, 0x20, 0x01, 0x00, 0x12, 0x34])
        peripheral.writeValue(request, for: status, in: ServiceUUID.PUMP_SERVICE)
        wait(for: [answered], timeout: 2)

        XCTAssertEqual(server.writes.map(\.value), [request])
        XCTAssertEqual(server.writes.first?.characteristic, status)
        XCTAssertEqual(
            events.events.dropFirst(),
            [.wroteValue(status), .updatedValue(status, response)],
            "write_ack must be delivered as didWriteValue before the notify becomes didUpdateValue"
        )
    }

    func testNotificationsRouteToDidUpdateValueOnlyWhileSubscribed() throws {
        central.delegate = recorder
        let peripheral = try connectPeripheral()
        let events = PeripheralRecorder()
        peripheral.delegate = events
        let status = CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
        let control = CharacteristicUUID.CONTROL_CHARACTERISTICS
        let connection = try XCTUnwrap(server.latestAttachedConnection)

        XCTAssertFalse(connection.notify(status, Data([1])), "unsubscribed: the pump drops it")

        let subscribed = expectation(description: "subscribe_ack")
        events.onEvent = { if $0 == .notificationState(status) { subscribed.fulfill() } }
        peripheral.setNotifyValue(true, for: status, in: ServiceUUID.PUMP_SERVICE)
        wait(for: [subscribed], timeout: 2)

        let delivered = expectation(description: "notify")
        events.onEvent = { if case .updatedValue = $0 { delivered.fulfill() } }
        XCTAssertTrue(connection.notify(status, Data([2, 3])))
        XCTAssertFalse(connection.notify(control, Data([9])), "a different, unsubscribed characteristic")
        wait(for: [delivered], timeout: 2)

        XCTAssertEqual(events.events, [.notificationState(status), .updatedValue(status, Data([2, 3]))])
        XCTAssertEqual(connection.droppedNotifies, [status, control])
    }

    func testReadValueDeliversTheReadResult() throws {
        central.delegate = recorder
        let peripheral = try connectPeripheral()
        let events = PeripheralRecorder()
        peripheral.delegate = events

        let read = expectation(description: "read_result")
        events.onEvent = { if case .updatedValue = $0 { read.fulfill() } }
        peripheral.readValue(for: CharacteristicUUID.DIS_MODEL_NUMBER, in: ServiceUUID.DIS_SERVICE)
        wait(for: [read], timeout: 2)

        XCTAssertEqual(events.events, [.updatedValue(CharacteristicUUID.DIS_MODEL_NUMBER, Data("Mobi".utf8))])
    }

    func testPumpInitiatedDisconnectReachesTheCentralDelegate() throws {
        central.delegate = recorder
        let peripheral = try connectPeripheral()

        let dropped = expectation(description: "didDisconnect")
        var reported: Error?
        recorder.onDisconnect = { disconnected, error in
            XCTAssertTrue(disconnected === peripheral)
            reported = error
            dropped.fulfill()
        }
        try XCTUnwrap(server.latestAttachedConnection).drop(reason: "fault_injection")
        wait(for: [dropped], timeout: 5)

        XCTAssertFalse(peripheral.isConnected)
        XCTAssertEqual(reported as? SocketPumpError, .pumpDisconnected(reason: "fault_injection"))
        XCTAssertTrue(central.retrieveConnectedPeripherals(withServices: [ServiceUUID.PUMP_SERVICE]).isEmpty)
    }

    func testCancelPeripheralConnectionReportsACleanDisconnect() throws {
        central.delegate = recorder
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
        XCTAssertFalse(peripheral.isConnected)
    }

    func testReconnectAfterDisconnectReusesThePeripheral() throws {
        central.delegate = recorder
        let peripheral = try connectPeripheral()

        let dropped = expectation(description: "didDisconnect")
        recorder.onDisconnect = { _, _ in dropped.fulfill() }
        try XCTUnwrap(server.latestAttachedConnection).drop(reason: "restart")
        wait(for: [dropped], timeout: 5)

        let again = try connectPeripheral()
        XCTAssertTrue(again === peripheral)
        XCTAssertTrue(peripheral.isConnected)
        XCTAssertEqual(server.attachCount, 2)
    }

    /// The real driver on top of the socket: TandemPeripheralManager packetizes an unsigned request,
    /// the pump answers with a packetized response, and the parsed message comes back to the caller.
    func testPeripheralManagerRoundTripsAnApiVersionRequest() throws {
        central.delegate = recorder
        let peripheral = try connectPeripheral()
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
        central.delegate = recorder
        let peripheral = try connectPeripheral()
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

    /// Same round trip against a running faketandem (`go run . -transport virtual`), reached at
    /// TANDEMKIT_VIRTUAL_PUMP_SMOKE=host:port (pass it as TEST_RUNNER_TANDEMKIT_VIRTUAL_PUMP_SMOKE to
    /// xcodebuild). The pump must be in a connectable pairing state. Skipped otherwise.
    func testApiVersionRoundTripAgainstARealVirtualPump() throws {
        guard let address = ProcessInfo.processInfo.environment["TANDEMKIT_VIRTUAL_PUMP_SMOKE"],
              let endpoint = SocketPumpEndpoint(address)
        else {
            throw XCTSkip("TANDEMKIT_VIRTUAL_PUMP_SMOKE not set")
        }
        let real = SocketPumpCentral(endpoint: endpoint, scanInterval: 0.5)
        real.delegate = recorder
        defer {
            for peripheral in real.retrieveConnectedPeripherals(withServices: []) {
                real.cancelPeripheralConnection(peripheral)
            }
        }

        let discovered = expectation(description: "didDiscover")
        discovered.assertForOverFulfill = false
        var scanned: PumpPeripheral?
        recorder.onDiscover = { peripheral, _ in
            scanned = peripheral
            discovered.fulfill()
        }
        real.scanForPeripherals(withServices: [ServiceUUID.PUMP_SERVICE], allowDuplicates: true)
        wait(for: [discovered], timeout: 5)
        real.stopScan()
        let peripheral = try XCTUnwrap(scanned)

        let connected = expectation(description: "didConnect")
        recorder.onConnect = { _ in connected.fulfill() }
        recorder.onFailToConnect = { _, error in XCTFail("connect failed: \(String(describing: error))") }
        real.connect(peripheral)
        wait(for: [connected], timeout: 5)

        let peripheralManager = makePeripheralManager(for: peripheral)
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
        wait(for: [answered], timeout: 35)
        XCTAssertNotNil(received)
        XCTAssertGreaterThan(received?.majorVersion ?? 0, 0)
    }

    private func makePeripheralManager(for peripheral: PumpPeripheral) -> TandemPeripheralManager {
        let bluetooth = TandemBluetoothManager(central: InertCentral())
        let pumpManager = TandemPumpManager(
            state: TandemPumpManagerState(rawValue: [:]),
            bluetooth: StubPumpBluetooth()
        )
        return TandemPeripheralManager(bluetooth, peripheral, pumpManager) { _ in }
    }
}
