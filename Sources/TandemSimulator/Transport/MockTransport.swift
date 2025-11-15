import Foundation
import Logging
import TandemCore

/// Mock in-memory transport for testing without BLE
class MockTransport: SimulatorTransport {
    private let logger = Logger(label: "TandemSimulator.MockTransport")

    // Queues for each characteristic (pump receives on these)
    private var receiveQueues: [CharacteristicUUID: PacketQueue] = [:]

    // Queues for responses (pump sends on these)
    private var sendQueues: [CharacteristicUUID: PacketQueue] = [:]

    private let lock = NSLock()
    private var _isConnected = false

    var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isConnected
    }

    init() {
        // Initialize queues for all characteristics
        let characteristics: [CharacteristicUUID] = [
            .AUTHORIZATION_CHARACTERISTICS,
            .CURRENT_STATUS_CHARACTERISTICS,
            .HISTORY_LOG_CHARACTERISTICS,
            .QUALIFYING_EVENTS_CHARACTERISTICS,
            .CONTROL_CHARACTERISTICS,
            .CONTROL_STREAM_CHARACTERISTICS
        ]

        for char in characteristics {
            receiveQueues[char] = PacketQueue()
            sendQueues[char] = PacketQueue()
        }
    }

    // MARK: - SimulatorTransport

    func start() async throws {
        logger.info("Mock transport starting")
        lock.lock()
        _isConnected = true
        lock.unlock()
        logger.info("Mock transport started and connected")
    }

    func stop() async throws {
        logger.info("Mock transport stopping")
        lock.lock()
        _isConnected = false
        lock.unlock()

        // Clear all queues
        for queue in receiveQueues.values {
            queue.clear()
        }
        for queue in sendQueues.values {
            queue.clear()
        }

        logger.info("Mock transport stopped")
    }

    func readPacket(for characteristic: CharacteristicUUID, timeout: TimeInterval) async throws -> Data? {
        guard isConnected else {
            throw MockTransportError.notConnected
        }

        guard let queue = receiveQueues[characteristic] else {
            throw MockTransportError.unknownCharacteristic(characteristic)
        }

        return await queue.dequeue(timeout: timeout)
    }

    func writePacket(_ data: Data, to characteristic: CharacteristicUUID) async throws {
        guard isConnected else {
            throw MockTransportError.notConnected
        }

        guard let queue = sendQueues[characteristic] else {
            throw MockTransportError.unknownCharacteristic(characteristic)
        }

        logger.debug("Writing packet to \(characteristic.prettyName): \(data.hexadecimalString)")
        queue.enqueue(data)
    }

    func notify(_ data: Data, on characteristic: CharacteristicUUID) async throws {
        // For mock transport, notify is the same as write
        try await writePacket(data, to: characteristic)
    }

    // MARK: - Test Helpers

    /// Inject a packet into the receive queue (simulates client sending to pump)
    func injectPacket(_ data: Data, on characteristic: CharacteristicUUID) {
        guard let queue = receiveQueues[characteristic] else {
            logger.error("Cannot inject packet on unknown characteristic: \(characteristic.rawValue)")
            return
        }

        logger.debug("Injecting packet on \(characteristic.prettyName): \(data.hexadecimalString)")
        queue.enqueue(data)
    }

    /// Read a packet from the send queue (simulates client reading pump response)
    func readResponse(from characteristic: CharacteristicUUID, timeout: TimeInterval = 5.0) async -> Data? {
        guard let queue = sendQueues[characteristic] else {
            logger.error("Cannot read response from unknown characteristic: \(characteristic.rawValue)")
            return nil
        }

        return await queue.dequeue(timeout: timeout)
    }

    /// Get access to send queue for testing
    func getSendQueue(for characteristic: CharacteristicUUID) -> PacketQueue? {
        sendQueues[characteristic]
    }

    /// Get access to receive queue for testing
    func getReceiveQueue(for characteristic: CharacteristicUUID) -> PacketQueue? {
        receiveQueues[characteristic]
    }
}

// MARK: - Packet Queue

/// Thread-safe queue for packet data
class PacketQueue {
    private var packets: [Data] = []
    private let lock = NSLock()
    private var waitingContinuations: [CheckedContinuation<Data?, Never>] = []

    func enqueue(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }

        packets.append(data)

        // Resume any waiting continuations
        if let continuation = waitingContinuations.first {
            waitingContinuations.removeFirst()
            continuation.resume(returning: data)
            packets.removeLast() // Remove the packet we just returned
        }
    }

    func dequeue(timeout: TimeInterval) async -> Data? {
        // First check if there's a packet available
        lock.lock()
        if !packets.isEmpty {
            let packet = packets.removeFirst()
            lock.unlock()
            return packet
        }
        lock.unlock()

        // No packet available, wait for one
        return await withCheckedContinuation { continuation in
            lock.lock()
            defer { lock.unlock() }

            // Check again in case a packet arrived
            if !packets.isEmpty {
                let packet = packets.removeFirst()
                continuation.resume(returning: packet)
                return
            }

            // Add continuation to waiting list
            waitingContinuations.append(continuation)

            // Schedule timeout
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))

                self.lock.lock()
                defer { self.lock.unlock() }

                // Find and remove the continuation if still waiting
                if let index = self.waitingContinuations.firstIndex(where: { _ in
                    // Can't compare continuations directly, so we just take the first one
                    // This works because we process in FIFO order
                    true
                }) {
                    let cont = self.waitingContinuations.remove(at: index)
                    cont.resume(returning: nil)
                }
            }
        }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }

        packets.removeAll()

        // Resume all waiting continuations with nil
        for continuation in waitingContinuations {
            continuation.resume(returning: nil)
        }
        waitingContinuations.removeAll()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return packets.count
    }
}

// MARK: - Errors

enum MockTransportError: Error, LocalizedError {
    case notConnected
    case unknownCharacteristic(CharacteristicUUID)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Mock transport is not connected"
        case let .unknownCharacteristic(char):
            return "Unknown characteristic: \(char.rawValue)"
        }
    }
}
