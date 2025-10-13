//
//  PeripheralManagerTransport.swift
//  TandemKit
//
//  Created by Claude Code on 1/11/25.
//
//  Concrete implementation of PumpMessageTransport that bridges PeripheralManager
//  from TandemBLE to PumpComm for actual pump communication.

import Foundation
import Dispatch
import TandemCore
import TandemBLE
#if canImport(os)
import os
#endif

/// Concrete implementation of PumpMessageTransport using PeripheralManager from TandemBLE
public final class PeripheralManagerTransport: PumpMessageTransport {
    private let peripheralManager: PeripheralManager
    private var currentTxId: UInt8 = 0
    private let log = OSLog(category: "PeripheralManagerTransport")
    private var requestResponseHistory: [RequestResponsePair] = []
    private let maxHistorySize = 100  // Keep last 100 exchanges

    public init(peripheralManager: PeripheralManager) {
        self.peripheralManager = peripheralManager
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
        // Create wrapper with current TxId
        let wrapper = try withMainActor {
            TronMessageWrapper(message: message, currentTxId: self.currentTxId)
        }
        let txIdForRequest = currentTxId
        currentTxId = currentTxId &+ 1 // Increment with overflow

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

        log.debug("Sending message: %{public}@ (TxId: %d)", String(describing: message), txIdForRequest)
        if wrapper.packets.isEmpty {
            print("[PeripheralManagerTransport] send message=\(message) txId=\(currentTxId &- 1) pkts=0")
        } else {
            print("[PeripheralManagerTransport] send message=\(message) txId=\(currentTxId &- 1) pkts=\(wrapper.packets.count)")
            for (index, packet) in wrapper.packets.enumerated() {
                let hex = packet.build.map { String(format: "%02X", $0) }.joined()
                print("[PeripheralManagerTransport]   packet \(index) len=\(packet.build.count) hex=\(hex)")
            }
        }

        let collector = PumpResponseCollector(wrapper: wrapper)

        // Send packets via PeripheralManager synchronously on its queue
        let sendResult = peripheralManager.performSync { manager in
            manager.sendMessagePackets(wrapper.packets, characteristic: characteristic)
        }

        // Handle send errors
        switch sendResult {
        case .unsentWithError(let error):
            log.error("Failed to send message: %{public}@", String(describing: error))
            print("[PeripheralManagerTransport] sendResult=unsentWithError error=\(error)")
            throw error
        case .sentWithError(let error):
            log.error("Message sent but pump returned error: %{public}@", String(describing: error))
            print("[PeripheralManagerTransport] sendResult=sentWithError error=\(error)")
            throw error
        case .sentWithAcknowledgment:
            log.debug("Message sent successfully")
            print("[PeripheralManagerTransport] sendResult=sentWithAcknowledgment")
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

            log.debug("Received response: %{public}@ bytes", String(describing: data.count))
            let responseHex = data.map { String(format: "%02X", $0) }.joined()
            print("[PeripheralManagerTransport] received \(data.count) bytes hex=\(responseHex)")

            let pumpResponse: PumpResponseMessage
            do {
                pumpResponse = try withMainActor {
                    try collector.ingest(data, characteristic: characteristic.cbUUID)
                }
            } catch {
                log.error("Failed to parse response chunk: %{public}@", String(describing: error))
                throw PumpCommError.other
            }

            if let responseMessage = pumpResponse.message {
                print("[PeripheralManagerTransport] parsed response message=\(responseMessage)")
                parsedMessage = responseMessage
            } else {
                print("[PeripheralManagerTransport] awaiting additional packets for \(message)")
            }
        }

        guard let finalMessage = parsedMessage else {
            log.error("No message parsed from pump response")
            throw PumpCommError.other
        }

        log.debug("Parsed response message: %{public}@", String(describing: finalMessage))

        // Add completed pair to history
        let completedPair = historyEntry.withResponse(finalMessage)
        requestResponseHistory.append(completedPair)

        // Trim history if needed
        if requestResponseHistory.count > maxHistorySize {
            requestResponseHistory.removeFirst(requestResponseHistory.count - maxHistorySize)
        }

        return finalMessage
    }

    // MARK: - History Query Methods

    /// Get all request-response pairs in history
    public func getHistory() -> [RequestResponsePair] {
        requestResponseHistory
    }

    /// Get the request that corresponds to a specific response
    public func getRequestForResponse(_ response: Message) -> Message? {
        // First try to find by type association
        if let requestType = MessageRegistry.requestMetadata(for: response)?.type {
            // Find most recent matching request in history
            for pair in requestResponseHistory.reversed() {
                if type(of: pair.request) == requestType,
                   let pairResponse = pair.response,
                   type(of: pairResponse) == type(of: response) {
                    return pair.request
                }
            }
        }
        return nil
    }

    /// Get the response that corresponds to a specific request
    public func getResponseForRequest(_ request: Message) -> Message? {
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
        requestResponseHistory.filter { type(of: $0.request) == requestType }
    }

    /// Get all pairs matching a specific TxId
    public func getPairForTxId(_ txId: UInt8) -> RequestResponsePair? {
        requestResponseHistory.first { $0.txId == txId }
    }

    /// Clear the request-response history
    public func clearHistory() {
        requestResponseHistory.removeAll()
    }
}
