#if TANDEMKIT_VIRTUAL_PUMP
import CoreBluetooth
import Foundation
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

// faketandem's virtual GATT link (see the protocol notes in the faketandem repo): one TCP
// connection per BLE connection, newline-delimited JSON, binary as lowercase hex. Plain POSIX
// sockets so the Linux SwiftPM build compiles it too.

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

extension [String: Any] {
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
        #if canImport(Glibc)
        hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
        #else
        hints.ai_socktype = SOCK_STREAM
        #endif
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
        Glue.suppressSigpipe(connected)
        fd = connected
    }

    /// Wraps an already-connected descriptor (the server side of a loopback test).
    init(fd: Int32) {
        Glue.suppressSigpipe(fd)
        self.fd = fd
    }

    func send(_ message: [String: Any]) throws {
        try send(line: JSONSerialization.data(withJSONObject: message))
    }

    /// One already-encoded JSON value; the newline is added here.
    func send(line: Data) throws {
        var line = line
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
        guard let line = try readLine(timeout: timeout) else {
            return nil
        }
        guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            throw SocketPumpError.protocolError("not a JSON object: \(String(decoding: line, as: UTF8.self))")
        }
        return object
    }

    /// Next non-empty line, without its newline, or nil at EOF. `timeout` nil blocks indefinitely.
    func readLine(timeout: TimeInterval?) throws -> Data? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                if line.isEmpty {
                    continue
                }
                return line
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

/// A TCP listener on 127.0.0.1 only, handing each accepted connection to `onAccept` on its own thread.
final class SocketListener {
    let port: UInt16
    private let stopped = StopFlag()

    /// `port` 0 takes an ephemeral one, read back from `port`.
    init(port: UInt16 = 0, name: String, onAccept: @escaping (SocketLink) -> Void) throws {
        #if canImport(Glibc)
        let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        guard fd >= 0 else {
            throw SocketPumpError.connectFailed("socket: \(String(cString: strerror(errno)))")
        }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            let reason = String(cString: strerror(errno))
            Glue.close(fd)
            throw SocketPumpError.connectFailed("bind/listen 127.0.0.1:\(port): \(reason)")
        }

        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &assigned) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        self.port = UInt16(bigEndian: assigned.sin_port)

        let stopped = self.stopped
        let thread = Thread {
            // Only this thread closes the socket: closed by stop() while this loop could still accept,
            // its number went to the next socket opened, and the loop took that socket's connections.
            defer { Glue.close(fd) }
            while !stopped.isSet {
                var listening = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                guard poll(&listening, 1, 100) > 0, !stopped.isSet else {
                    continue
                }
                let client = accept(fd, nil, nil)
                guard client >= 0 else {
                    continue
                }
                let link = SocketLink(fd: client)
                let connection = Thread { onAccept(link) }
                connection.name = "\(name).connection"
                connection.start()
            }
        }
        thread.name = "\(name).accept"
        thread.start()
    }

    /// Stops accepting, and frees the port within 100 ms; connections already handed out stay open.
    func stop() {
        stopped.set()
    }

    deinit {
        stop()
    }
}

private final class StopFlag {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
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

    /// Writing to a closed peer must fail with EPIPE, not SIGPIPE-kill the process (tests run both ends in one).
    static func suppressSigpipe(_ fd: Int32) {
        #if !canImport(Glibc)
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        #endif
    }

    static func write(_ fd: Int32, _ buf: UnsafeRawPointer, _ count: Int) -> Int {
        #if canImport(Glibc)
        Glibc.send(fd, buf, count, Int32(MSG_NOSIGNAL))
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
