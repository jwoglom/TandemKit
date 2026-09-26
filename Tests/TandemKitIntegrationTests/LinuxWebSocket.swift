#if !canImport(ObjectiveC)
import Foundation
import Glibc

/// swift-corelibs-foundation's URLSessionWebSocketTask needs a libcurl built with WebSocket
/// support, and the Swift toolchain's is not. faketandem listens on loopback, so plain ws:// with
/// RFC 6455 text frames is all FaketandemControlSocket needs.
final class LinuxWebSocket {
    enum Failure: Error, CustomStringConvertible {
        case connect(String)
        case handshake(String)
        case closed

        var description: String {
            switch self {
            case let .connect(detail): return "websocket connect failed: \(detail)"
            case let .handshake(detail): return "websocket handshake failed: \(detail)"
            case .closed: return "websocket closed"
            }
        }
    }

    private let host: String
    private let port: UInt16
    private let path: String
    private var fd: Int32 = -1
    private let writeLock = NSLock()

    init(url: URL) {
        host = url.host ?? "127.0.0.1"
        port = UInt16(url.port ?? 80)
        path = url.path.isEmpty ? "/" : url.path
    }

    /// Connects and completes the upgrade, then delivers each text message on a reader thread
    /// until the connection ends, which is reported once through `onFailure`.
    func connect(onText: @escaping (String) -> Void, onFailure: @escaping (Error) -> Void) throws {
        fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        guard fd >= 0 else { throw Failure.connect("socket() errno \(errno)") }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        let numericHost = host == "localhost" ? "127.0.0.1" : host
        guard inet_pton(AF_INET, numericHost, &address.sin_addr) == 1 else {
            throw Failure.connect("\(host) is not an IPv4 address")
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Glibc.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { throw Failure.connect("connect() errno \(errno)") }

        let key = Data((0 ..< 16).map { _ in UInt8.random(in: 0 ... 255) }).base64EncodedString()
        let request = "GET \(path) HTTP/1.1\r\nHost: \(host):\(port)\r\nUpgrade: websocket\r\n"
            + "Connection: Upgrade\r\nSec-WebSocket-Key: \(key)\r\nSec-WebSocket-Version: 13\r\n\r\n"
        try writeAll(Data(request.utf8))

        // Byte by byte, so nothing past the headers is consumed before the frame reader starts.
        var head = Data()
        while !head.hasSuffix([13, 10, 13, 10]) {
            head.append(try readExactly(1))
        }
        let status = String(decoding: head, as: UTF8.self)
        guard status.hasPrefix("HTTP/1.1 101") else {
            throw Failure.handshake(status.components(separatedBy: "\r\n").first ?? status)
        }

        let thread = Thread { [self] in
            do {
                while true {
                    if let text = try readMessage() {
                        onText(text)
                    }
                }
            } catch {
                onFailure(error)
            }
        }
        thread.name = "LinuxWebSocket reader"
        thread.start()
    }

    func send(_ text: String) throws {
        try writeFrame(opcode: 0x1, payload: Data(text.utf8))
    }

    func close() {
        try? writeFrame(opcode: 0x8, payload: Data())
        shutdown(fd, Int32(SHUT_RDWR))
        Glibc.close(fd)
    }

    /// A whole text message, or nil after a control frame.
    private func readMessage() throws -> String? {
        var message = Data()
        while true {
            let header = try readExactly(2)
            let isFinal = header[0] & 0x80 != 0
            let opcode = header[0] & 0x0F
            var length = UInt64(header[1] & 0x7F)
            if length == 126 {
                length = try readExactly(2).reduce(0) { $0 << 8 | UInt64($1) }
            } else if length == 127 {
                length = try readExactly(8).reduce(0) { $0 << 8 | UInt64($1) }
            }
            let mask = header[1] & 0x80 != 0 ? [UInt8](try readExactly(4)) : nil
            var payload = [UInt8](try readExactly(Int(length)))
            if let mask {
                for index in payload.indices {
                    payload[index] ^= mask[index % 4]
                }
            }

            switch opcode {
            case 0x0, 0x1, 0x2:
                message.append(contentsOf: payload)
                if isFinal {
                    return String(decoding: message, as: UTF8.self)
                }
            case 0x8:
                throw Failure.closed
            case 0x9:
                try writeFrame(opcode: 0xA, payload: Data(payload))
                return nil
            default:
                return nil
            }
        }
    }

    /// Client frames must be masked (RFC 6455 5.3).
    private func writeFrame(opcode: UInt8, payload: Data) throws {
        var frame = Data([0x80 | opcode])
        let length = payload.count
        if length < 126 {
            frame.append(0x80 | UInt8(length))
        } else if length <= Int(UInt16.max) {
            frame.append(0x80 | 126)
            frame.append(contentsOf: [UInt8(length >> 8 & 0xFF), UInt8(length & 0xFF)])
        } else {
            frame.append(0x80 | 127)
            frame.append(contentsOf: (0 ..< 8).reversed().map { UInt8(UInt64(length) >> (UInt64($0) * 8) & 0xFF) })
        }
        let mask = (0 ..< 4).map { _ in UInt8.random(in: 0 ... 255) }
        frame.append(contentsOf: mask)
        frame.append(contentsOf: payload.enumerated().map { $0.element ^ mask[$0.offset % 4] })

        writeLock.lock()
        defer { writeLock.unlock() }
        try writeAll(frame)
    }

    private func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < buffer.count {
                let sent = Glibc.send(fd, buffer.baseAddress! + offset, buffer.count - offset, Int32(MSG_NOSIGNAL))
                if sent < 0 {
                    if errno == EINTR { continue }
                    throw Failure.closed
                }
                offset += sent
            }
        }
    }

    private func readExactly(_ count: Int) throws -> Data {
        var data = Data(count: count)
        var offset = 0
        while offset < count {
            let received = data.withUnsafeMutableBytes { buffer in
                recv(fd, buffer.baseAddress! + offset, count - offset, 0)
            }
            if received < 0, errno == EINTR { continue }
            guard received > 0 else { throw Failure.closed }
            offset += received
        }
        return data
    }
}

private extension Data {
    func hasSuffix(_ bytes: [UInt8]) -> Bool {
        count >= bytes.count && Array(suffix(bytes.count)) == bytes
    }
}
#endif
