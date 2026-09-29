#if TANDEMKIT_VIRTUAL_PUMP
#if !DEBUG
#error("TANDEMKIT_VIRTUAL_PUMP swaps CoreBluetooth for a socket to faketandem; it must never reach a release build")
#endif
import CoreBluetooth
import Foundation

// Stand-ins for the CoreBluetooth classes the driver uses, carried over faketandem's virtual GATT
// link. Declarations in this module shadow CoreBluetooth's everywhere in it, so the driver compiles
// against these unchanged; CBUUID, CBManagerState and the other value types stay the real ones.
// Only the API surface the driver touches is here, with CoreBluetooth's threading: every delegate
// callback is delivered asynchronously on the central's queue.

public enum VirtualPump {
    /// `host:port` of the faketandem virtual GATT link, read from the app process's environment.
    public static let environmentVariable = "TANDEMKIT_VIRTUAL_PUMP"

    /// Used by every `CBCentralManager(delegate:queue:)` created afterwards.
    static var endpoint: SocketPumpEndpoint? = ProcessInfo.processInfo.environment[environmentVariable]
        .flatMap(SocketPumpEndpoint.init)
    static var scanInterval: TimeInterval = 1.0

    /// Replace the driver's 30 s response and connect timeouts, which are sized for a real pump's
    /// slowest command. faketandem answers at once or, when a test tells it not to, never.
    static var responseTimeout: DispatchTimeInterval?
    static var connectTimeout: DispatchTimeInterval?
}

public enum CBPeripheralState: Int {
    case disconnected
    case connecting
    case connected
    case disconnecting
}

public protocol CBCentralManagerDelegate: AnyObject {
    func centralManagerDidUpdateState(_ central: CBCentralManager)
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    )
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral)
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?)
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?)
}

public extension CBCentralManagerDelegate {
    func centralManager(_: CBCentralManager, didDiscover _: CBPeripheral, advertisementData _: [String: Any], rssi _: NSNumber) {}
    func centralManager(_: CBCentralManager, didConnect _: CBPeripheral) {}
    func centralManager(_: CBCentralManager, didDisconnectPeripheral _: CBPeripheral, error _: Error?) {}
    func centralManager(_: CBCentralManager, didFailToConnect _: CBPeripheral, error _: Error?) {}
}

public protocol CBPeripheralDelegate: AnyObject {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?)
}

public extension CBPeripheralDelegate {
    func peripheral(_: CBPeripheral, didDiscoverServices _: Error?) {}
    func peripheral(_: CBPeripheral, didDiscoverCharacteristicsFor _: CBService, error _: Error?) {}
    func peripheral(_: CBPeripheral, didUpdateValueFor _: CBCharacteristic, error _: Error?) {}
    func peripheral(_: CBPeripheral, didWriteValueFor _: CBCharacteristic, error _: Error?) {}
    func peripheral(_: CBPeripheral, didUpdateNotificationStateFor _: CBCharacteristic, error _: Error?) {}
}

public final class CBService: NSObject {
    public let uuid: CBUUID
    public private(set) weak var peripheral: CBPeripheral?

    private let lock = NSLock()
    private var _characteristics: [CBCharacteristic]?

    init(uuid: CBUUID, peripheral: CBPeripheral) {
        self.uuid = uuid
        self.peripheral = peripheral
    }

    public var characteristics: [CBCharacteristic]? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _characteristics
        }
        set {
            lock.lock()
            _characteristics = newValue
            lock.unlock()
        }
    }
}

public final class CBCharacteristic: NSObject {
    public let uuid: CBUUID
    public private(set) weak var service: CBService?

    private let lock = NSLock()
    private var _value: Data?

    init(uuid: CBUUID, service: CBService) {
        self.uuid = uuid
        self.service = service
    }

    /// The last read result or notification, set before the matching `didUpdateValueFor`.
    public internal(set) var value: Data? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            _value = newValue
            lock.unlock()
        }
    }
}

public final class CBCentralManager: NSObject {
    private let logger = TandemLogger(category: "VirtualCBCentralManager")
    let endpoint: SocketPumpEndpoint?
    let queue: DispatchQueue
    private let scanInterval: TimeInterval

    private let lock = NSLock()
    private weak var _delegate: CBCentralManagerDelegate?
    private var _isScanning = false
    private var scanGeneration = 0
    private var scanAllowsDuplicates = true
    private var scanServices: [CBUUID]?
    private var reportedThisScan: Set<UUID> = []
    private var peripherals: [UUID: CBPeripheral] = [:]

    public convenience init(delegate: CBCentralManagerDelegate?, queue: DispatchQueue?, options _: [String: Any]? = nil) {
        self.init(delegate: delegate, queue: queue, endpoint: VirtualPump.endpoint, scanInterval: VirtualPump.scanInterval)
    }

    init(delegate: CBCentralManagerDelegate?, queue: DispatchQueue?, endpoint: SocketPumpEndpoint?, scanInterval: TimeInterval) {
        _delegate = delegate
        self.queue = queue ?? .main
        self.endpoint = endpoint
        self.scanInterval = scanInterval
        super.init()
        if let endpoint {
            logger.warning("TANDEMKIT_VIRTUAL_PUMP build: no real Bluetooth; pump is faketandem at \(endpoint.host):\(endpoint.port)")
        } else {
            logger.error("\(VirtualPump.environmentVariable) is not set to host:port; Bluetooth reports unsupported")
        }
        self.queue.async {
            self.delegate?.centralManagerDidUpdateState(self)
        }
    }

    public var delegate: CBCentralManagerDelegate? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _delegate
        }
        set {
            lock.lock()
            _delegate = newValue
            lock.unlock()
        }
    }

    public var state: CBManagerState { endpoint == nil ? .unsupported : .poweredOn }

    public var isScanning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isScanning
    }

    // MARK: Scanning

    /// A "scan" is a TCP connection opened just long enough to read `hello`, reported as one
    /// advertisement, repeated every `scanInterval` while scanning so pairing-state changes in the
    /// manufacturer data show up the way repeated advertisements would.
    public func scanForPeripherals(withServices services: [CBUUID]?, options: [String: Any]? = nil) {
        guard let endpoint else {
            logger.error("scanForPeripherals with no virtual pump endpoint")
            return
        }
        lock.lock()
        _isScanning = true
        scanGeneration += 1
        scanServices = services
        scanAllowsDuplicates = options?[CBCentralManagerScanOptionAllowDuplicatesKey] as? Bool ?? false
        reportedThisScan = []
        let generation = scanGeneration
        lock.unlock()
        scanProbe(endpoint, generation: generation)
    }

    public func stopScan() {
        lock.lock()
        _isScanning = false
        scanGeneration += 1
        lock.unlock()
    }

    private func isScanning(generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isScanning && scanGeneration == generation
    }

    /// Whether this scan should report `hello` now: it advertises a requested service, and has not
    /// been reported yet unless the scan allows duplicates.
    private func claimAdvertisement(_ hello: VirtualPumpHello, generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard _isScanning, scanGeneration == generation else {
            return false
        }
        if let scanServices, !scanServices.isEmpty,
           !scanServices.contains(where: { wanted in hello.services.contains { $0.service == wanted } })
        {
            return false
        }
        if scanAllowsDuplicates {
            return true
        }
        return reportedThisScan.insert(hello.peripheralId).inserted
    }

    private func scanProbe(_ endpoint: SocketPumpEndpoint, generation: Int) {
        DispatchQueue.global(qos: .utility).async {
            defer {
                if self.isScanning(generation: generation) {
                    self.queue.asyncAfter(deadline: .now() + self.scanInterval) {
                        self.scanProbe(endpoint, generation: generation)
                    }
                }
            }
            guard self.isScanning(generation: generation) else {
                return
            }
            do {
                let link = try SocketLink(connectTo: endpoint)
                defer { link.close() }
                let hello = try Self.readHello(from: link)
                // The pump answers hello in every state so a probe can tell why it is refused, but
                // a real pump that is not discoverable is not advertising, so there is nothing to
                // report.
                guard hello.pairingState != VirtualPumpHello.notDiscoverablePairingState else {
                    return
                }
                let peripheral = self.peripheral(for: hello.peripheralId)
                peripheral.apply(hello)
                guard self.claimAdvertisement(hello, generation: generation) else {
                    return
                }
                self.queue.async {
                    self.delegate?.centralManager(
                        self,
                        didDiscover: peripheral,
                        advertisementData: hello.advertisementData,
                        rssi: NSNumber(value: -50)
                    )
                }
            } catch {
                self.logger.warning("Scan probe of \(endpoint.host):\(endpoint.port) failed: \(error)")
            }
        }
    }

    static func readHello(from link: SocketLink) throws -> VirtualPumpHello {
        guard let message = try link.readMessage(timeout: 5) else {
            throw SocketPumpError.protocolError("connection closed before hello")
        }
        guard let hello = VirtualPumpHello(message) else {
            throw SocketPumpError.protocolError("expected hello, got \(message["type"] ?? "nothing")")
        }
        return hello
    }

    /// One object per identifier, as CoreBluetooth hands out while it holds the peripheral.
    private func peripheral(for identifier: UUID) -> CBPeripheral {
        lock.lock()
        defer { lock.unlock() }
        if let existing = peripherals[identifier] {
            return existing
        }
        let created = CBPeripheral(identifier: identifier, central: self)
        peripherals[identifier] = created
        return created
    }

    // MARK: Connecting

    public func connect(_ peripheral: CBPeripheral, options _: [String: Any]? = nil) {
        guard let endpoint else {
            logger.error("connect with no virtual pump endpoint")
            return
        }
        let attempt = SocketConnectAttempt()
        guard peripheral.beginConnecting(attempt) else {
            logger.warning("connect ignored; \(peripheral.identifier) is already connecting or connected")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let link = try SocketLink(connectTo: endpoint)
                attempt.link = link
                let hello = try Self.readHello(from: link)
                guard hello.peripheralId == peripheral.identifier else {
                    link.close()
                    throw SocketPumpError.peripheralMismatch(expected: peripheral.identifier, actual: hello.peripheralId)
                }
                peripheral.apply(hello)

                try link.send(["type": "attach", "id": 1])
                while true {
                    guard let reply = try link.readMessage(timeout: 5) else {
                        throw SocketPumpError.protocolError("connection closed before attach_ack")
                    }
                    let type = reply["type"] as? String
                    if type == "attach_ack" {
                        break
                    }
                    if type == "disconnect" {
                        link.close()
                        throw SocketPumpError.pumpDisconnected(reason: reply["reason"] as? String ?? "unknown")
                    }
                }

                guard peripheral.finishConnecting(attempt, link: link) else {
                    // Cancelled during the handshake; CoreBluetooth reports nothing for a cancelled
                    // pending connect either.
                    link.close()
                    return
                }
                self.queue.async {
                    self.delegate?.centralManager(self, didConnect: peripheral)
                }
                self.runReader(link: link, peripheral: peripheral)
            } catch {
                guard peripheral.failConnecting(attempt) else {
                    return
                }
                self.logger.error("Connect to \(endpoint.host):\(endpoint.port) failed: \(error)")
                self.queue.async {
                    self.delegate?.centralManager(self, didFailToConnect: peripheral, error: error)
                }
            }
        }
    }

    /// Blocks the calling (global) thread reading the link until it closes, dispatching every
    /// message onto `queue`. EOF is the BLE disconnect.
    private func runReader(link: SocketLink, peripheral: CBPeripheral) {
        var disconnectReason: String?
        var readError: Error?
        do {
            while let message = try link.readMessage(timeout: nil) {
                if message["type"] as? String == "disconnect" {
                    disconnectReason = message["reason"] as? String ?? "unknown"
                    continue
                }
                queue.async {
                    peripheral.handle(message)
                }
            }
        } catch {
            readError = error
        }
        link.close()

        let cancelledLocally = peripheral.detach(link)
        let error: Error? = if let disconnectReason {
            SocketPumpError.pumpDisconnected(reason: disconnectReason)
        } else if cancelledLocally {
            nil
        } else {
            readError ?? SocketPumpError.pumpDisconnected(reason: "connection closed")
        }
        queue.async {
            self.delegate?.centralManager(self, didDisconnectPeripheral: peripheral, error: error)
        }
    }

    public func cancelPeripheralConnection(_ peripheral: CBPeripheral) {
        peripheral.cancelConnection()
    }

    /// Any identifier is retrievable: the link reconnects to the configured endpoint whatever the
    /// peripheral is called, and the hello check on connect catches a mismatch.
    public func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [CBPeripheral] {
        identifiers.map { peripheral(for: $0) }
    }

    public func retrieveConnectedPeripherals(withServices services: [CBUUID]) -> [CBPeripheral] {
        lock.lock()
        let all = Array(peripherals.values)
        lock.unlock()
        return all.filter { $0.state == .connected && $0.offersServices(services) }
    }
}

/// One connect() in flight; lets a cancel break the handshake's blocking reads.
final class SocketConnectAttempt {
    private let lock = NSLock()
    private var _link: SocketLink?

    var link: SocketLink? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _link
        }
        set {
            lock.lock()
            _link = newValue
            lock.unlock()
        }
    }
}

public final class CBPeripheral: NSObject {
    private let logger = TandemLogger(category: "VirtualCBPeripheral")
    public let identifier: UUID
    private weak var central: CBCentralManager?
    private let queue: DispatchQueue

    private enum Pending {
        case read(CBCharacteristic)
        case write(CBCharacteristic)
        case writeWithoutResponse
        case subscribe(CBCharacteristic)
    }

    private enum LinkState {
        case disconnected
        case connecting(SocketConnectAttempt)
        case connected(SocketLink)
    }

    private let lock = NSLock()
    private weak var _delegate: CBPeripheralDelegate?
    private var _name: String?
    private var _services: [CBService]?
    /// The GATT table from `hello`; what discovery can find.
    private var gatt: [(service: CBUUID, characteristics: [CBUUID])] = []
    private var linkState: LinkState = .disconnected
    private var cancelRequested = false
    private var pending: [Int: Pending] = [:]
    private var nextRequestId = 2 // 1 is attach

    init(identifier: UUID, central: CBCentralManager) {
        self.identifier = identifier
        self.central = central
        queue = central.queue
    }

    public var name: String? {
        lock.lock()
        defer { lock.unlock() }
        return _name
    }

    public var delegate: CBPeripheralDelegate? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _delegate
        }
        set {
            lock.lock()
            _delegate = newValue
            lock.unlock()
        }
    }

    /// Updated before the matching central callback is delivered.
    public var state: CBPeripheralState {
        lock.lock()
        defer { lock.unlock() }
        switch linkState {
        case .disconnected: return .disconnected
        case .connecting: return .connecting
        case .connected: return .connected
        }
    }

    /// Nil until `didDiscoverServices`, and again after a disconnect.
    public var services: [CBService]? {
        lock.lock()
        defer { lock.unlock() }
        return _services
    }

    func apply(_ hello: VirtualPumpHello) {
        lock.lock()
        _name = hello.name
        gatt = hello.services
        lock.unlock()
    }

    func offersServices(_ services: [CBUUID]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return services.allSatisfy { wanted in gatt.contains { $0.service == wanted } }
    }

    // MARK: Link lifecycle (driven by the central)

    func beginConnecting(_ attempt: SocketConnectAttempt) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard case .disconnected = linkState else {
            return false
        }
        linkState = .connecting(attempt)
        cancelRequested = false
        return true
    }

    /// False if the attempt was cancelled or superseded meanwhile.
    func finishConnecting(_ attempt: SocketConnectAttempt, link: SocketLink) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard case let .connecting(current) = linkState, current === attempt, !cancelRequested else {
            linkState = .disconnected
            return false
        }
        linkState = .connected(link)
        pending = [:]
        return true
    }

    /// False if the attempt was cancelled, in which case nothing is reported.
    func failConnecting(_ attempt: SocketConnectAttempt) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard case let .connecting(current) = linkState, current === attempt else {
            return false
        }
        linkState = .disconnected
        return !cancelRequested
    }

    /// Returns whether the drop was requested locally (cancelPeripheralConnection).
    func detach(_ link: SocketLink) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if case let .connected(current) = linkState, current === link {
            linkState = .disconnected
        }
        pending = [:]
        _services = nil
        let cancelled = cancelRequested
        cancelRequested = false
        return cancelled
    }

    func cancelConnection() {
        lock.lock()
        cancelRequested = true
        let state = linkState
        lock.unlock()

        switch state {
        case .disconnected:
            lock.lock()
            cancelRequested = false
            lock.unlock()
        case let .connecting(attempt):
            attempt.link?.shutdown()
        case let .connected(link):
            try? link.send(["type": "disconnect", "id": allocateRequestId()])
            link.shutdown()
        }
    }

    private func allocateRequestId() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let id = nextRequestId
        nextRequestId += 1
        return id
    }

    // MARK: GATT

    /// Discovery is answered from `hello`'s GATT table without a round trip to the pump.
    public func discoverServices(_ serviceUUIDs: [CBUUID]?) {
        guard state == .connected else {
            logger.error("discoverServices on a peripheral that is not connected")
            return
        }
        queue.async {
            self.lock.lock()
            let existing = self._services ?? []
            self._services = self.gatt
                .filter { entry in serviceUUIDs?.contains(entry.service) ?? true }
                .map { entry in
                    existing.first(where: { $0.uuid == entry.service }) ?? CBService(uuid: entry.service, peripheral: self)
                }
            self.lock.unlock()
            self.delegate?.peripheral(self, didDiscoverServices: nil)
        }
    }

    public func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]?, for service: CBService) {
        guard state == .connected else {
            logger.error("discoverCharacteristics on a peripheral that is not connected")
            return
        }
        queue.async {
            self.lock.lock()
            let offered = self.gatt.first(where: { $0.service == service.uuid })?.characteristics
            self.lock.unlock()
            guard let offered else {
                let error = SocketPumpError.protocolError("unknown service \(service.uuid.uuidString)")
                self.delegate?.peripheral(self, didDiscoverCharacteristicsFor: service, error: error)
                return
            }
            let existing = service.characteristics ?? []
            let found = offered
                .filter { characteristicUUIDs?.contains($0) ?? true }
                .map { uuid in existing.first(where: { $0.uuid == uuid }) ?? CBCharacteristic(uuid: uuid, service: service) }
            service.characteristics = existing.filter { old in !found.contains { $0 === old } } + found
            self.delegate?.peripheral(self, didDiscoverCharacteristicsFor: service, error: nil)
        }
    }

    public func readValue(for characteristic: CBCharacteristic) {
        send(["type": "read", "characteristic": characteristic.uuid.virtualPumpString], pending: .read(characteristic))
    }

    public func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) {
        let withResponse = type == .withResponse
        send(
            [
                "type": "write",
                "characteristic": characteristic.uuid.virtualPumpString,
                "value": data.hexadecimalString,
                "with_response": withResponse,
            ],
            pending: withResponse ? .write(characteristic) : .writeWithoutResponse
        )
    }

    public func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic) {
        send(
            ["type": "subscribe", "characteristic": characteristic.uuid.virtualPumpString, "enabled": enabled],
            pending: .subscribe(characteristic)
        )
    }

    /// Writes to the socket on the caller's thread; the reply comes back through `handle` on the
    /// central's queue. Like CoreBluetooth, a request on a disconnected peripheral goes nowhere.
    private func send(_ message: [String: Any], pending request: Pending) {
        lock.lock()
        guard case let .connected(link) = linkState else {
            lock.unlock()
            logger.error("Not connected; dropping \(message["type"] ?? "")")
            return
        }
        let id = nextRequestId
        nextRequestId += 1
        pending[id] = request
        lock.unlock()

        var message = message
        message["id"] = id
        do {
            try link.send(message)
        } catch {
            logger.error("Send failed: \(error)")
            lock.lock()
            pending[id] = nil
            lock.unlock()
        }
    }

    private func discoveredCharacteristic(_ uuid: CBUUID) -> CBCharacteristic? {
        for service in services ?? [] {
            if let characteristic = service.characteristics?.first(where: { $0.uuid == uuid }) {
                return characteristic
            }
        }
        return nil
    }

    /// Runs on the central's queue.
    func handle(_ message: [String: Any]) {
        guard let type = message["type"] as? String else {
            logger.warning("Message without type: \(message)")
            return
        }
        let error: Error? = (message["error"] as? String).map { SocketPumpError.protocolError($0) }
        let value = (message["value"] as? String).flatMap { Data(hexadecimalString: $0) }

        switch type {
        case "notify":
            guard let uuid = message.virtualPumpCharacteristic else {
                logger.warning("notify without characteristic")
                return
            }
            // CoreBluetooth cannot deliver a notification for a characteristic it has not discovered.
            guard let characteristic = discoveredCharacteristic(uuid) else {
                logger.warning("notify for undiscovered characteristic \(uuid.uuidString)")
                return
            }
            characteristic.value = value
            delegate?.peripheral(self, didUpdateValueFor: characteristic, error: nil)

        case "write_ack", "read_result", "subscribe_ack":
            guard let id = message["id"] as? Int, let request = takePending(id) else {
                logger.warning("\(type) for unknown request id \(message["id"] ?? "nil")")
                return
            }
            switch request {
            case let .write(characteristic):
                delegate?.peripheral(self, didWriteValueFor: characteristic, error: error)
            case .writeWithoutResponse:
                break
            case let .read(characteristic):
                if error == nil {
                    characteristic.value = value
                }
                delegate?.peripheral(self, didUpdateValueFor: characteristic, error: error)
            case let .subscribe(characteristic):
                delegate?.peripheral(self, didUpdateNotificationStateFor: characteristic, error: error)
            }

        case "error":
            logger.error("Virtual pump error: \(message["error"] ?? "") (id \(message["id"] ?? "nil"))")

        case "hello", "attach_ack":
            break

        default:
            logger.warning("Unhandled message type \(type)")
        }
    }

    private func takePending(_ id: Int) -> Pending? {
        lock.lock()
        defer { lock.unlock() }
        return pending.removeValue(forKey: id)
    }
}
#endif
