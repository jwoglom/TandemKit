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
        if wrapper.packets.isEmpty {
            print("[PeripheralManagerTransport] send message=\(message) txId=\(currentTxId &- 1) pkts=0")
        } else {
            print("[PeripheralManagerTransport] send message=\(message) txId=\(currentTxId &- 1) pkts=\(wrapper.packets.count)")
            for (index, packet) in wrapper.packets.enumerated() {
                let hex = packet.build.map { String(format: "%02X", $0) }.joined()
                print("[PeripheralManagerTransport]   packet \(index) len=\(packet.build.count) hex=\(hex)")
            }
        }

        let characteristic = type(of: message).props.characteristic
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
            let responsePreview = data.prefix(32).map { String(format: "%02X", $0) }.joined()
            print("[PeripheralManagerTransport] received \(data.count) bytes preview=\(responsePreview)…")

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
                parsedMessage = responseMessage
            } else {
                print("[PeripheralManagerTransport] awaiting additional packets for \(type(of: message))")
            }
        }

        guard let finalMessage = parsedMessage else {
            log.error("No message parsed from pump response")
            throw PumpCommError.other
        }

        log.debug("Parsed response message: %{public}@", String(describing: finalMessage))
        return finalMessage
    }
}
