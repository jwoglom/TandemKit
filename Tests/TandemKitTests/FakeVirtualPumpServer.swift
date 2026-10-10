#if TANDEMKIT_VIRTUAL_PUMP
import CoreBluetooth
import Foundation
@testable import TandemKit
import XCTest
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

/// Loopback stand-in for faketandem's virtual GATT link: listens on an ephemeral 127.0.0.1 port and
/// speaks the newline-delimited JSON protocol, one thread per connection.
final class FakeVirtualPumpServer {
    final class Connection {
        let link: SocketLink
        fileprivate(set) var attached = false
        private let lock = NSLock()
        private var subscribed: Set<CBUUID> = []
        private(set) var droppedNotifies: [CBUUID] = []

        fileprivate init(link: SocketLink) {
            self.link = link
        }

        func setSubscribed(_ enabled: Bool, _ characteristic: CBUUID) {
            lock.lock()
            defer { lock.unlock() }
            if enabled {
                subscribed.insert(characteristic)
            } else {
                subscribed.remove(characteristic)
            }
        }

        /// One ATT notification; dropped (and recorded) while the central is not subscribed, as
        /// the Go server does.
        @discardableResult
        func notify(_ characteristic: CBUUID, _ value: Data) -> Bool {
            lock.lock()
            let isSubscribed = subscribed.contains(characteristic)
            if !isSubscribed {
                droppedNotifies.append(characteristic)
            }
            lock.unlock()
            guard isSubscribed else {
                return false
            }
            try? link.send([
                "type": "notify",
                "characteristic": characteristic.virtualPumpString,
                "value": value.hexadecimalString,
            ])
            return true
        }

        /// Pump-initiated drop: `disconnect` then socket close.
        func drop(reason: String) {
            try? link.send(["type": "disconnect", "reason": reason])
            link.shutdown()
        }
    }

    let peripheralId = UUID()
    var name = "tslim X2 ***123"
    var manufacturerData = Data([0x00, 0x00, 0x00, 0x12])
    var pairingState = "PairStep2"
    var readValues: [CBUUID: Data] = [
        CharacteristicUUID.DIS_MANUFACTURER_NAME: Data("Tandem Diabetes Care".utf8),
        CharacteristicUUID.DIS_MODEL_NUMBER: Data("Mobi".utf8),
    ]
    /// Called after the write has been acknowledged, from the connection's thread.
    var onWrite: ((Connection, CBUUID, Data) -> Void)?
    var onAttach: ((Connection) -> Void)?

    private let lock = NSLock()
    private(set) var writes: [(characteristic: CBUUID, value: Data)] = []
    private(set) var attachCount = 0
    private(set) var helloCount = 0
    private var connections: [Connection] = []

    private var listener: SocketListener?

    var port: UInt16 { listener?.port ?? 0 }

    var endpoint: SocketPumpEndpoint { SocketPumpEndpoint(host: "127.0.0.1", port: port) }

    var latestAttachedConnection: Connection? {
        lock.lock()
        defer { lock.unlock() }
        return connections.last(where: \.attached)
    }

    func start() throws {
        listener = try SocketListener(name: "FakeVirtualPumpServer") { [weak self] link in
            guard let self else {
                return
            }
            let connection = Connection(link: link)
            lock.lock()
            connections.append(connection)
            lock.unlock()
            serve(connection)
        }
    }

    func stop() {
        lock.lock()
        let open = connections
        connections = []
        lock.unlock()
        listener?.stop()
        for connection in open {
            connection.link.shutdown()
        }
    }

    private var hello: [String: Any] {
        [
            "type": "hello",
            "protocol_version": 1,
            "peripheral_id": peripheralId.uuidString.lowercased(),
            "name": name,
            "manufacturer_data": manufacturerData.hexadecimalString,
            "pairing_state": pairingState,
            "services": [
                [
                    "uuid": ServiceUUID.PUMP_SERVICE.virtualPumpString,
                    "characteristics": CharacteristicUUID.allPumpCharacteristics.map {
                        [
                            "uuid": $0.virtualPumpString,
                            "properties": ["write", "write_without_response", "notify", "indicate"],
                        ]
                    },
                ],
                [
                    "uuid": ServiceUUID.DIS_SERVICE.virtualPumpString,
                    "characteristics": CharacteristicUUID.allDeviceInfoCharacteristics.map {
                        ["uuid": $0.virtualPumpString, "properties": ["read"]]
                    },
                ],
            ],
        ]
    }

    private func serve(_ connection: Connection) {
        let link = connection.link
        defer { link.close() }

        lock.lock()
        helloCount += 1
        lock.unlock()
        guard (try? link.send(hello)) != nil else {
            return
        }

        while let message = try? link.readMessage(timeout: nil) {
            let id = message["id"] as? Int
            guard let type = message["type"] as? String else {
                try? link.send(["type": "error", "error": "missing type"])
                continue
            }
            let characteristic = (message["characteristic"] as? String).flatMap(CBUUID.virtualPump)

            switch type {
            case "attach":
                lock.lock()
                connection.attached = true
                attachCount += 1
                lock.unlock()
                try? link.send(["type": "attach_ack", "id": id ?? 0])
                onAttach?(connection)

            case "write":
                guard let characteristic,
                      let value = (message["value"] as? String).flatMap({ Data(hexadecimalString: $0) })
                else {
                    try? link.send(["type": "write_ack", "id": id ?? 0, "error": "bad write"])
                    continue
                }
                lock.lock()
                writes.append((characteristic, value))
                lock.unlock()
                try? link.send(["type": "write_ack", "id": id ?? 0])
                onWrite?(connection, characteristic, value)

            case "read":
                if let characteristic, let value = readValues[characteristic] {
                    try? link.send(["type": "read_result", "id": id ?? 0, "value": value.hexadecimalString])
                } else {
                    try? link.send(["type": "read_result", "id": id ?? 0, "error": "read not permitted"])
                }

            case "subscribe":
                if let characteristic {
                    connection.setSubscribed(message["enabled"] as? Bool ?? true, characteristic)
                    try? link.send(["type": "subscribe_ack", "id": id ?? 0])
                } else {
                    try? link.send(["type": "subscribe_ack", "id": id ?? 0, "error": "unknown characteristic"])
                }

            case "disconnect":
                return

            default:
                var reply: [String: Any] = ["type": "error", "error": "unknown type"]
                if let id {
                    reply["id"] = id
                }
                try? link.send(reply)
            }
        }
    }
}
#endif
