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
        currentTxId = currentTxId &+ 1 // Increment with overflow

        log.debug("Sending message: %{public}@ (TxId: %d)", String(describing: message), currentTxId - 1)
        if let firstPacket = wrapper.packets.first {
            let hex = firstPacket.build.prefix(32).map { String(format: "%02X", $0) }.joined()
            print("[PeripheralManagerTransport] send \(type(of: message)) txId=\(currentTxId &- 1) pkts=\(wrapper.packets.count) first=\(hex)…")
        } else {
            print("[PeripheralManagerTransport] send \(type(of: message)) txId=\(currentTxId &- 1) pkts=0")
        }

        // Send packets via PeripheralManager synchronously on its queue
        let sendResult = peripheralManager.performSync { manager in
            manager.sendMessagePackets(wrapper.packets)
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

        // Read response packet
        let data = try peripheralManager.performSync { manager -> Data in
            guard let responseData = try manager.readMessagePacket() else {
                throw PumpCommError.noResponse
            }
            return responseData
        }

        guard !data.isEmpty else {
            log.error("No response data received")
            throw PumpCommError.noResponse
        }

        log.debug("Received response: %{public}@ bytes", String(describing: data.count))
        let responsePreview = data.prefix(32).map { String(format: "%02X", $0) }.joined()
        print("[PeripheralManagerTransport] received \(data.count) bytes preview=\(responsePreview)…")

        // Parse response using BTResponseParser
        let characteristicUUID = type(of: message).props.characteristic.cbUUID
        let pumpResponse = try withMainActor { () throws -> PumpResponseMessage in
            guard let response = BTResponseParser.parse(wrapper: wrapper,
                                                        output: data,
                                                        characteristic: characteristicUUID) else {
                throw PumpCommError.other
            }
            return response
        }

        // Get response message (currently returns RawMessage from BTResponseParser)
        guard let responseMessage = pumpResponse.message else {
            log.error("No message in parsed response")
            throw PumpCommError.other
        }

        log.debug("Parsed response message: %{public}@", String(describing: responseMessage))
        return responseMessage
    }
}
