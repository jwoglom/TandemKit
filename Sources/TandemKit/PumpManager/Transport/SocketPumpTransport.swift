#if DEBUG
import CoreBluetooth
import Foundation
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

// A PumpCentral over faketandem's virtual GATT link (see the protocol notes in the faketandem
// repo): one TCP connection per BLE connection, newline-delimited JSON, binary as lowercase hex.
// Plain POSIX sockets so the Linux SwiftPM build compiles it too.

struct SocketPumpEndpoint: Equatable {
    let host: String
    let port: UInt16

    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    /// `host:port`; a bare port means 127.0.0.1.
    init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = trimmed.lastIndex(of: ":") else {
            guard let port = UInt16(trimmed) else {
                return nil
            }
            self.init(host: "127.0.0.1", port: port)
            return
        }
        let host = String(trimmed[..<colon])
        guard !host.isEmpty, let port = UInt16(trimmed[trimmed.index(after: colon)...]) else {
            return nil
        }
        self.init(host: host, port: port)
    }
}

enum SocketPumpError: Error, Equatable {
    case connectFailed(String)
    case protocolError(String)
    case peripheralMismatch(expected: UUID, actual: UUID)
    case timedOut
    case pumpDisconnected(reason: String)
}

final class SocketPumpCentral: PumpCentral {
    private let logger = TandemLogger(category: "SocketPumpCentral")
    let endpoint: SocketPumpEndpoint
    /// Every central and peripheral callback is delivered here, asynchronously.
    let queue: DispatchQueue
    private let scanInterval: TimeInterval

    private let lock = NSLock()
    private weak var _delegate: PumpCentralDelegate?
    private var _isScanning = false
    private var scanGeneration = 0
    private var peripherals: [UUID: SocketPumpPeripheral] = [:]
    // Only touched on `queue`.
    private var announcedState = false

    init(
        endpoint: SocketPumpEndpoint,
        queue: DispatchQueue = DispatchQueue(label: "com.jwoglom.TandemKit.socketPumpCentral"),
        scanInterval: TimeInterval = 1.0
    ) {
        self.endpoint = endpoint
        self.queue = queue
        self.scanInterval = scanInterval
    }

    var state: CBManagerState { .poweredOn }

    var isScanning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isScanning
    }

    var delegate: PumpCentralDelegate? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _delegate
        }
        set {
            lock.lock()
            _delegate = newValue
            lock.unlock()
            queue.async {
                guard !self.announcedState, let delegate = self.delegate else {
                    return
                }
                self.announcedState = true
                delegate.centralDidUpdateState(self)
            }
        }
    }

    // MARK: Scanning

    /// A "scan" is a TCP connection opened just long enough to read `hello`, reported as one
    /// advertisement, repeated every `scanInterval` while scanning so pairing-state changes in the
    /// manufacturer data show up the way repeated advertisements would.
    func scanForPeripherals(withServices _: [CBUUID], allowDuplicates _: Bool) {
        lock.lock()
        _isScanning = true
        scanGeneration += 1
        let generation = scanGeneration
        lock.unlock()
        scanProbe(generation: generation)
    }

    func stopScan() {
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

    private func scanProbe(generation: Int) {
        DispatchQueue.global(qos: .utility).async {
            defer {
                if self.isScanning(generation: generation) {
                    self.queue.asyncAfter(deadline: .now() + self.scanInterval) {
                        self.scanProbe(generation: generation)
                    }
                }
            }
            guard self.isScanning(generation: generation) else {
                return
            }
            do {
                let link = try SocketLink(connectTo: self.endpoint)
                defer { link.close() }
                let hello = try Self.readHello(from: link)
                // The pump answers hello in every state so a probe can tell why it is refused, but
                // a real pump that is not discoverable is not advertising, so there is nothing to
                // report.
                guard hello.pairingState != VirtualPumpHello.notDiscoverablePairingState else {
                    return
                }
                let peripheral = self.peripheral(for: hello)
                guard self.isScanning(generation: generation) else {
                    return
                }
                self.queue.async {
                    self.delegate?.central(
                        self,
                        didDiscover: peripheral,
                        advertisementData: hello.advertisementData,
                        rssi: NSNumber(value: -50)
                    )
                }
            } catch {
                self.logger.warning("Scan probe of \(self.endpoint.host):\(self.endpoint.port) failed: \(error)")
            }
        }
    }

    private static func readHello(from link: SocketLink) throws -> VirtualPumpHello {
        guard let message = try link.readMessage(timeout: 5) else {
            throw SocketPumpError.protocolError("connection closed before hello")
        }
        guard let hello = VirtualPumpHello(message) else {
            throw SocketPumpError.protocolError("expected hello, got \(message["type"] ?? "nothing")")
        }
        return hello
    }

    private func peripheral(for hello: VirtualPumpHello) -> SocketPumpPeripheral {
        let peripheral = peripheral(for: hello.peripheralId)
        peripheral.apply(hello)
        return peripheral
    }

    private func peripheral(for identifier: UUID) -> SocketPumpPeripheral {
        lock.lock()
        defer { lock.unlock() }
        if let existing = peripherals[identifier] {
            return existing
        }
        let created = SocketPumpPeripheral(identifier: identifier, central: self)
        peripherals[identifier] = created
        return created
    }

    // MARK: Connecting

    func connect(_ peripheral: PumpPeripheral) {
        guard let peripheral = peripheral as? SocketPumpPeripheral else {
            logger.error("connect called with a non-socket peripheral: \(peripheral.identifier)")
            return
        }
        let attempt = SocketConnectAttempt()
        guard peripheral.beginConnecting(attempt) else {
            logger.warning("connect ignored; \(peripheral.identifier) is already connecting or connected")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let link = try SocketLink(connectTo: self.endpoint)
                attempt.link = link
                let hello = try Self.readHello(from: link)
                guard hello.peripheralId == peripheral.identifier else {
                    link.close()
                    throw SocketPumpError.peripheralMismatch(
                        expected: peripheral.identifier,
                        actual: hello.peripheralId
                    )
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
                    // Cancelled while we were in the handshake; the peripheral never counted as
                    // connected, so there is nothing to report (CoreBluetooth is silent here too).
                    link.close()
                    return
                }
                self.queue.async {
                    self.delegate?.central(self, didConnect: peripheral)
                }
                self.runReader(link: link, peripheral: peripheral)
            } catch {
                guard peripheral.failConnecting(attempt) else {
                    return
                }
                self.logger.error("Connect to \(self.endpoint.host):\(self.endpoint.port) failed: \(error)")
                self.queue.async {
                    self.delegate?.central(self, didFailToConnect: peripheral, error: error)
                }
            }
        }
    }

    /// Blocks the calling (global) thread reading the link until it closes, dispatching every
    /// message onto `queue`. EOF is the BLE disconnect.
    private func runReader(link: SocketLink, peripheral: SocketPumpPeripheral) {
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
            self.delegate?.central(self, didDisconnect: peripheral, error: error)
        }
    }

    func cancelPeripheralConnection(_ peripheral: PumpPeripheral) {
        guard let peripheral = peripheral as? SocketPumpPeripheral else {
            return
        }
        peripheral.cancelConnection()
    }

    func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [PumpPeripheral] {
        // Any identifier is retrievable: the link reconnects to the configured endpoint whatever
        // the peripheral is called, and the hello check on connect catches a mismatch.
        identifiers.map { peripheral(for: $0) }
    }

    func retrieveConnectedPeripherals(withServices services: [CBUUID]) -> [PumpPeripheral] {
        lock.lock()
        let all = Array(peripherals.values)
        lock.unlock()
        return all.filter { peripheral in
            peripheral.isConnected && services.allSatisfy { peripheral.discoveredServices.contains($0) }
        }
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

final class SocketPumpPeripheral: PumpPeripheral {
    private let logger = TandemLogger(category: "SocketPumpPeripheral")
    let identifier: UUID
    private unowned let central: SocketPumpCentral
    private var queue: DispatchQueue { central.queue }

    private enum Pending {
        case read(CBUUID)
        case write(CBUUID)
        case subscribe(CBUUID)
    }

    private enum LinkState {
        case disconnected
        case connecting(SocketConnectAttempt)
        case connected(SocketLink)
    }

    private let lock = NSLock()
    private weak var _delegate: PumpPeripheralDelegate?
    private var _name: String?
    private var services: [(service: CBUUID, characteristics: [CBUUID])] = []
    private var linkState: LinkState = .disconnected
    private var cancelRequested = false
    private var pending: [Int: Pending] = [:]
    private var nextRequestId = 2 // 1 is attach

    init(identifier: UUID, central: SocketPumpCentral) {
        self.identifier = identifier
        self.central = central
    }

    var name: String? {
        lock.lock()
        defer { lock.unlock() }
        return _name
    }

    var delegate: PumpPeripheralDelegate? {
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

    var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .connected = linkState {
            return true
        }
        return false
    }

    var discoveredServices: [CBUUID] {
        lock.lock()
        defer { lock.unlock() }
        return services.map(\.service)
    }

    func apply(_ hello: VirtualPumpHello) {
        lock.lock()
        _name = hello.name
        services = hello.services
        lock.unlock()
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

    // MARK: PumpPeripheral

    func discoverServices(_: [CBUUID]) {
        queue.async {
            self.delegate?.peripheral(self, didDiscoverServices: nil)
        }
    }

    func discoverCharacteristics(_: [CBUUID], for service: CBUUID) {
        let known = discoveredServices.contains(service)
        queue.async {
            let error: Error? = known ? nil : SocketPumpError.protocolError("unknown service \(service.uuidString)")
            self.delegate?.peripheral(self, didDiscoverCharacteristicsFor: service, error: error)
        }
    }

    func hasCharacteristic(_ characteristic: CBUUID, in service: CBUUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return services.first(where: { $0.service == service })?.characteristics.contains(characteristic) ?? false
    }

    func readValue(for characteristic: CBUUID, in _: CBUUID) {
        send(["type": "read", "characteristic": characteristic.virtualPumpString], pending: .read(characteristic))
    }

    func writeValue(_ data: Data, for characteristic: CBUUID, in _: CBUUID) {
        send(
            [
                "type": "write",
                "characteristic": characteristic.virtualPumpString,
                "value": data.hexadecimalString,
                "with_response": true,
            ],
            pending: .write(characteristic)
        )
    }

    func setNotifyValue(_ enabled: Bool, for characteristic: CBUUID, in _: CBUUID) {
        send(
            ["type": "subscribe", "characteristic": characteristic.virtualPumpString, "enabled": enabled],
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

    /// Runs on the central's queue.
    func handle(_ message: [String: Any]) {
        guard let type = message["type"] as? String else {
            logger.warning("Message without type: \(message)")
            return
        }
        let error: Error? = (message["error"] as? String).map { SocketPumpError.protocolError($0) }

        switch type {
        case "notify":
            guard let characteristic = message.virtualPumpCharacteristic else {
                logger.warning("notify without characteristic")
                return
            }
            let value = (message["value"] as? String).flatMap { Data(hexadecimalString: $0) }
            delegate?.peripheral(self, didUpdateValueFor: characteristic, value: value, error: nil)

        case "write_ack", "read_result", "subscribe_ack":
            guard let id = message["id"] as? Int, let request = takePending(id) else {
                logger.warning("\(type) for unknown request id \(message["id"] ?? "nil")")
                return
            }
            switch request {
            case let .write(characteristic):
                delegate?.peripheral(self, didWriteValueFor: characteristic, error: error)
            case let .read(characteristic):
                let value = (message["value"] as? String).flatMap { Data(hexadecimalString: $0) }
                delegate?.peripheral(self, didUpdateValueFor: characteristic, value: value, error: error)
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

/// The `hello` frame the peripheral sends on every connection.
struct VirtualPumpHello {
    static let notDiscoverablePairingState = "NotDiscoverable"

    let peripheralId: UUID
    let name: String
    let manufacturerData: Data?
    let pairingState: String?
    let services: [(service: CBUUID, characteristics: [CBUUID])]

    init?(_ message: [String: Any]) {
        guard message["type"] as? String == "hello",
              let idString = message["peripheral_id"] as? String,
              let id = UUID(uuidString: idString)
        else {
            return nil
        }
        peripheralId = id
        name = message["name"] as? String ?? ""
        manufacturerData = (message["manufacturer_data"] as? String).flatMap { Data(hexadecimalString: $0) }
        pairingState = message["pairing_state"] as? String
        services = (message["services"] as? [[String: Any]] ?? []).compactMap { service in
            guard let uuid = (service["uuid"] as? String).flatMap(CBUUID.virtualPump) else {
                return nil
            }
            let characteristics = (service["characteristics"] as? [[String: Any]] ?? [])
                .compactMap { ($0["uuid"] as? String).flatMap(CBUUID.virtualPump) }
            return (uuid, characteristics)
        }
    }

    var advertisementData: [String: Any] {
        var data: [String: Any] = [CBAdvertisementDataLocalNameKey: name]
        if let manufacturerData {
            data[CBAdvertisementDataManufacturerDataKey] = manufacturerData
        }
        return data
    }
}

private extension [String: Any] {
    var virtualPumpCharacteristic: CBUUID? {
        (self["characteristic"] as? String).flatMap(CBUUID.virtualPump)
    }
}

extension CBUUID {
    private static let baseSuffix = "-0000-1000-8000-00805f9b34fb"

    /// The link always uses full 128-bit lowercase strings; CoreBluetooth shortens Bluetooth base
    /// UUIDs to 16 bits.
    var virtualPumpString: String {
        let string = uuidString.lowercased()
        switch string.count {
        case 4:
            return "0000\(string)\(Self.baseSuffix)"
        case 8:
            return "\(string)\(Self.baseSuffix)"
        default:
            return string
        }
    }

    static func virtualPump(_ string: String) -> CBUUID? {
        guard UUID(uuidString: string) != nil else {
            return nil
        }
        return CBUUID(string: string)
    }
}

/// A connected TCP socket speaking newline-delimited JSON. `readMessage` is for one reader thread;
/// `send` may be called from any thread; `shutdown` from any thread unblocks the reader.
final class SocketLink {
    private let fd: Int32
    private let writeLock = NSLock()
    private let stateLock = NSLock()
    private var isShutDown = false
    private var isClosed = false
    private var buffer: [UInt8] = []

    init(connectTo endpoint: SocketPumpEndpoint) throws {
        var hints = addrinfo()
        hints.ai_socktype = Int32(SOCK_STREAM)
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(endpoint.host, String(endpoint.port), &hints, &result)
        guard status == 0, let first = result else {
            throw SocketPumpError
                .connectFailed("getaddrinfo(\(endpoint.host)): \(String(cString: gai_strerror(status)))")
        }
        defer { freeaddrinfo(result) }

        var lastError = "no addresses"
        var connected: Int32 = -1
        var candidate: UnsafeMutablePointer<addrinfo>? = first
        while let info = candidate, connected < 0 {
            candidate = info.pointee.ai_next
            let sock = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
            guard sock >= 0 else {
                lastError = String(cString: strerror(errno))
                continue
            }
            if Glue.connect(sock, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 {
                connected = sock
            } else {
                lastError = String(cString: strerror(errno))
                Glue.close(sock)
            }
        }
        guard connected >= 0 else {
            throw SocketPumpError.connectFailed("connect(\(endpoint.host):\(endpoint.port)): \(lastError)")
        }
        var one: Int32 = 1
        setsockopt(connected, Int32(IPPROTO_TCP), TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
        fd = connected
    }

    /// Wraps an already-connected descriptor (the server side of a loopback test).
    init(fd: Int32) {
        self.fd = fd
    }

    func send(_ message: [String: Any]) throws {
        var line = try JSONSerialization.data(withJSONObject: message)
        line.append(UInt8(0x0A))
        writeLock.lock()
        defer { writeLock.unlock() }
        try line.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < raw.count {
                let written = Glue.write(fd, raw.baseAddress! + offset, raw.count - offset)
                if written < 0 {
                    if errno == EINTR {
                        continue
                    }
                    throw SocketPumpError.connectFailed("write: \(String(cString: strerror(errno)))")
                }
                offset += written
            }
        }
    }

    /// Next JSON object, or nil at EOF. `timeout` nil blocks indefinitely.
    func readMessage(timeout: TimeInterval?) throws -> [String: Any]? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                if line.isEmpty {
                    continue
                }
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw SocketPumpError.protocolError("not a JSON object: \(String(decoding: line, as: UTF8.self))")
                }
                return object
            }

            if let timeout {
                var pollfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let ready = poll(&pollfd, 1, Int32(timeout * 1000))
                if ready == 0 {
                    throw SocketPumpError.timedOut
                }
                if ready < 0, errno != EINTR {
                    throw SocketPumpError.connectFailed("poll: \(String(cString: strerror(errno)))")
                }
            }

            var chunk = [UInt8](repeating: 0, count: 4096)
            let count = Glue.read(fd, &chunk, chunk.count)
            if count == 0 {
                return nil
            }
            if count < 0 {
                if errno == EINTR {
                    continue
                }
                return nil
            }
            buffer.append(contentsOf: chunk[0 ..< count])
        }
    }

    /// Breaks a blocked `readMessage` on another thread with EOF. The descriptor itself is released
    /// by `close`, which only the reader should call, so a recycled descriptor can never be read.
    func shutdown() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isShutDown, !isClosed else {
            return
        }
        isShutDown = true
        Glue.shutdown(fd, Int32(SHUT_RDWR))
    }

    func close() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isClosed else {
            return
        }
        isClosed = true
        Glue.close(fd)
    }

    deinit {
        close()
    }
}

/// The libc calls, named so they are not shadowed by this file's own methods.
private enum Glue {
    static func connect(_ fd: Int32, _ addr: UnsafePointer<sockaddr>?, _ len: socklen_t) -> Int32 {
        #if canImport(Glibc)
        Glibc.connect(fd, addr, len)
        #else
        Darwin.connect(fd, addr, len)
        #endif
    }

    static func write(_ fd: Int32, _ buf: UnsafeRawPointer, _ count: Int) -> Int {
        #if canImport(Glibc)
        Glibc.write(fd, buf, count)
        #else
        Darwin.write(fd, buf, count)
        #endif
    }

    static func read(_ fd: Int32, _ buf: UnsafeMutableRawPointer, _ count: Int) -> Int {
        #if canImport(Glibc)
        Glibc.read(fd, buf, count)
        #else
        Darwin.read(fd, buf, count)
        #endif
    }

    static func shutdown(_ fd: Int32, _ how: Int32) {
        #if canImport(Glibc)
        _ = Glibc.shutdown(fd, how)
        #else
        _ = Darwin.shutdown(fd, how)
        #endif
    }

    static func close(_ fd: Int32) {
        #if canImport(Glibc)
        _ = Glibc.close(fd)
        #else
        _ = Darwin.close(fd)
        #endif
    }
}
#endif
