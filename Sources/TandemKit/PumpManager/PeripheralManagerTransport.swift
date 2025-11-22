import Dispatch
import Foundation
import TandemBLE
import TandemCore
#if canImport(os)
    import os
#endif

private let transportLogger = PumpLogger(label: "TandemKit.PeripheralManagerTransport")

/// Concrete implementation of PumpMessageTransport using PeripheralManager from TandemBLE
public final class PeripheralManagerTransport: PumpMessageTransport {
    private let peripheralManager: PeripheralManager
    private var currentTxId: UInt8 = 0
    private let log = OSLog(category: "PeripheralManagerTransport")
    private var requestResponseHistory: [RequestResponsePair] = []
    private let maxHistorySize = 100 // Keep last 100 exchanges
    private let txIdLock = NSLock() // Protects currentTxId from concurrent access

    // Request throttling to prevent BLE write queue saturation
    private let throttleLock = NSLock()
    private var lastSendTimestamp: Date?
    private let minimumDelayBetweenSends: TimeInterval = 0.15 // 150ms between sends

    // Protects requestResponseHistory from concurrent access
    private let historyLock = NSLock()

    public init(peripheralManager: PeripheralManager) {
        self.peripheralManager = peripheralManager
        let instanceId = ObjectIdentifier(self)
        log.info("PeripheralManagerTransport init: instance=%{public}@", String(describing: instanceId))
        transportLogger.info("[PeripheralManagerTransport] init: instance=\(instanceId) currentTxId=0")
    }

    private func withMainActor<T>(_ block: @MainActor @escaping () throws -> T) throws -> T {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated { try block() }
        }

        var result: Result<T, Error>?
        let semaphore = DispatchSemaphore(value: 0)
        Task { @MainActor in
            result = Result { try block() }
            semaphore.signal()
        }
        semaphore.wait()

        guard let unwrapped = result else {
            fatalError("withMainActor completed without producing a result")
        }

        return try unwrapped.get()
    }

    public func sendMessage(_ message: Message) throws -> Message {
        let instanceId = ObjectIdentifier(self)

        // Apply request throttling to prevent BLE write queue saturation
        throttleLock.lock()
        if let lastSend = lastSendTimestamp {
            let timeSinceLastSend = Date().timeIntervalSince(lastSend)
            let remainingDelay = minimumDelayBetweenSends - timeSinceLastSend

            if remainingDelay > 0 {
                transportLogger.debug(
                    "[PeripheralManagerTransport] Throttling: waiting \(String(format: "%.0f", remainingDelay * 1000))ms before sending \(String(describing: type(of: message)))"
                )
                throttleLock.unlock()
                Thread.sleep(forTimeInterval: remainingDelay)
                throttleLock.lock()
            }
        }
        lastSendTimestamp = Date()
        throttleLock.unlock()

        // Atomically assign txId and create wrapper (protected by lock)
        txIdLock.lock()
        let txIdForRequest = currentTxId
        transportLogger.info("[PeripheralManagerTransport] sendMessage called: instance=\(instanceId) currentTxId=\(currentTxId)")

        // Create wrapper with current TxId while holding lock
        let wrapper: TronMessageWrapper
        do {
            wrapper = try withMainActor {
                TronMessageWrapper(message: message, currentTxId: txIdForRequest)
            }
        } catch {
            txIdLock.unlock()
            throw error
        }

        // Increment after wrapper is created successfully
        currentTxId = currentTxId &+ 1 // Increment with overflow
        let nextTxId = currentTxId
        txIdLock.unlock()

        transportLogger.info("[PeripheralManagerTransport] txId assigned: \(txIdForRequest), next will be: \(nextTxId)")

        // Create initial history entry (no response yet)
        let characteristic = type(of: message).props.characteristic
        let historyEntry = RequestResponsePair(
            request: message,
            requestMetadata: wrapper.requestMetadata,
            response: nil,
            responseMetadata: wrapper.responseMetadata,
            txId: txIdForRequest,
            timestamp: Date(),
            characteristic: characteristic
        )

        let requestCargo = message.cargo.map { String(format: "%d", Int8(bitPattern: $0)) }.joined(separator: ",")
        log.info(
            "  SENT-MESSAGE(txId=%-3d, %{public}@):\t%{public}@[cargo={%{public}@}]",
            txIdForRequest,
            characteristic.prettyName,
            String(describing: wrapper.requestMetadata.name),
            requestCargo
        )
        if wrapper.packets.isEmpty {
            transportLogger.error("[PeripheralManagerTransport] no packets for message=\(message) txId=\(currentTxId &- 1)")
            throw PumpCommError.invalidPacket
        } else {
            transportLogger
                .debug(
                    "[PeripheralManagerTransport] send message=\(message) txId=\(currentTxId &- 1) pkts=\(wrapper.packets.count)"
                )
            for (index, packet) in wrapper.packets.enumerated() {
                let hex = packet.build.map { String(format: "%02X", $0) }.joined()
                transportLogger.debug("[PeripheralManagerTransport]   packet \(index) len=\(packet.build.count) hex=\(hex)")

                // Break down packet structure for debugging
                if packet.build.count >= 5 {
                    let packetsRemaining = packet.build[0]
                    let txId = packet.build[1]
                    let opCode = packet.build[2]
                    let sizeOrFlags = packet.build.count > 3 ? packet.build[3] : 0
                    let cargoStart = packet.build.count > 4 ? packet.build.dropFirst(4).prefix(8)
                        .map { String(format: "%02X", $0) }.joined() : ""
                    transportLogger
                        .debug(
                            "[PeripheralManagerTransport]     packetsRemaining=\(packetsRemaining) txId=\(txId) opCode=\(opCode) sizeOrFlags=\(sizeOrFlags) cargoStart=\(cargoStart)"
                        )
                }
            }
        }

        let collector = PumpResponseCollector(wrapper: wrapper)

        // Send packets via PeripheralManager synchronously on its queue
        let sendResult = peripheralManager.performSync { manager in
            manager.sendMessagePackets(wrapper.packets, characteristic: characteristic)
        }

        // Handle send errors
        switch sendResult {
        case let .unsentWithError(error):
            log.error("Failed to send message: %{public}@", String(describing: error))
            transportLogger.error("[PeripheralManagerTransport] sendResult=unsentWithError error=\(error)")
            throw error
        case let .sentWithError(error):
            log.error("Message sent but pump returned error: %{public}@", String(describing: error))
            transportLogger.error("[PeripheralManagerTransport] sendResult=sentWithError error=\(error)")
            throw error
        case .sentWithAcknowledgment:
            log.debug("  → Message sent (txId=%d)", txIdForRequest)
            transportLogger.debug("[PeripheralManagerTransport] sendResult=sentWithAcknowledgment")
        }

        var parsedMessage: Message?

        while parsedMessage == nil {
            let data = try peripheralManager.performSync { manager -> Data in
                guard let responseData = try manager.readMessagePacket(for: characteristic, timeout: 15) else {
                    throw PumpCommError.noResponse
                }
                return responseData
            }

            guard !data.isEmpty else {
                log.error("No response data received")
                throw PumpCommError.noResponse
            }

            log.debug("  ← Received %{public}@ bytes (txId=%d)", String(describing: data.count), txIdForRequest)
            let responseHex = data.map { String(format: "%02X", $0) }.joined()
            transportLogger.debug("[PeripheralManagerTransport] received \(data.count) bytes hex=\(responseHex)")

            // Break down received packet structure for debugging
            if data.count >= 5 {
                let packetsRemaining = data[0]
                let rxTxId = data[1]
                let rxOpCode = data[2]
                let rxSizeOrFlags = data[3]
                let cargoStart = data.count > 4 ? data.dropFirst(4).prefix(8).map { String(format: "%02X", $0) }.joined() : ""
                transportLogger
                    .debug(
                        "[PeripheralManagerTransport]   packetsRemaining=\(packetsRemaining) rxTxId=\(rxTxId) opCode=\(rxOpCode) sizeOrFlags=\(rxSizeOrFlags) cargoStart=\(cargoStart)"
                    )
            }

            let pumpResponse: PumpResponseMessage
            do {
                pumpResponse = try withMainActor {
                    try collector.ingest(data, characteristic: characteristic.cbUUID)
                }
            } catch {
                log.error("Failed to parse response chunk: %{public}@", String(describing: error))
                throw PumpCommError.responseParsingFailed(underlying: error)
            }

            if let responseMessage = pumpResponse.message {
                transportLogger.debug("[PeripheralManagerTransport] parsed response message=\(responseMessage)")
                parsedMessage = responseMessage
            } else {
                transportLogger.debug("[PeripheralManagerTransport] awaiting additional packets for \(message)")
            }
        }

        guard let finalMessage = parsedMessage else {
            log.error("No message parsed from pump response")
            throw PumpCommError.noResponse
        }

        let responseType = String(describing: type(of: finalMessage))
        let responseCargo = finalMessage.cargo.map { String(format: "%d", Int8(bitPattern: $0)) }.joined(separator: ",")
        log.info(
            "PARSED-MESSAGE(txId=%-3d, %{public}@):\t%{public}@[cargo={%{public}@}]",
            txIdForRequest,
            characteristic.prettyName,
            responseType,
            responseCargo
        )

        // Add completed pair to history (thread-safe)
        let completedPair = historyEntry.withResponse(finalMessage)
        historyLock.lock()
        requestResponseHistory.append(completedPair)

        // Trim history if needed
        if requestResponseHistory.count > maxHistorySize {
            requestResponseHistory.removeFirst(requestResponseHistory.count - maxHistorySize)
        }
        historyLock.unlock()

        return finalMessage
    }

    // MARK: - History Query Methods

    /// Get all request-response pairs in history
    public func getHistory() -> [RequestResponsePair] {
        historyLock.lock()
        defer { historyLock.unlock() }
        return requestResponseHistory
    }

    /// Get the request that corresponds to a specific response
    public func getRequestForResponse(_ response: Message) -> Message? {
        historyLock.lock()
        defer { historyLock.unlock() }

        // First try to find by type association
        if let requestType = MessageRegistry.requestMetadata(for: response)?.type {
            // Find most recent matching request in history
            for pair in requestResponseHistory.reversed() {
                if type(of: pair.request) == requestType,
                   let pairResponse = pair.response,
                   type(of: pairResponse) == type(of: response)
                {
                    return pair.request
                }
            }
        }
        return nil
    }

    /// Get the response that corresponds to a specific request
    public func getResponseForRequest(_ request: Message) -> Message? {
        historyLock.lock()
        defer { historyLock.unlock() }

        // Find in history by request instance or type
        for pair in requestResponseHistory.reversed() {
            if type(of: pair.request) == type(of: request) {
                return pair.response
            }
        }
        return nil
    }

    /// Get all pairs matching a specific request type
    public func getPairsForRequestType(_ requestType: Message.Type) -> [RequestResponsePair] {
        historyLock.lock()
        defer { historyLock.unlock() }
        return requestResponseHistory.filter { type(of: $0.request) == requestType }
    }

    /// Get all pairs matching a specific TxId
    public func getPairForTxId(_ txId: UInt8) -> RequestResponsePair? {
        historyLock.lock()
        defer { historyLock.unlock() }
        return requestResponseHistory.first { $0.txId == txId }
    }

    /// Clear the request-response history
    public func clearHistory() {
        historyLock.lock()
        defer { historyLock.unlock() }
        requestResponseHistory.removeAll()
    }
}
