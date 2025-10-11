//
//  PeripheralManagerTransport.swift
//  TandemKit
//
//  Created by Claude Code on 1/11/25.
//
//  Concrete implementation of PumpMessageTransport that bridges PeripheralManager
//  from TandemBLE to PumpComm for actual pump communication.

import Foundation
import TandemCore
import TandemBLE
#if canImport(os)
import os
#endif

/// Concrete implementation of PumpMessageTransport using PeripheralManager from TandemBLE
@MainActor
class PeripheralManagerTransport: PumpMessageTransport {
    private let peripheralManager: PeripheralManager
    private var currentTxId: UInt8 = 0
    private let log = OSLog(category: "PeripheralManagerTransport")

    init(peripheralManager: PeripheralManager) {
        self.peripheralManager = peripheralManager
    }

    func sendMessage(_ message: Message) throws -> Message {
        // Create wrapper with current TxId
        let wrapper = TronMessageWrapper(message: message, currentTxId: currentTxId)
        currentTxId = currentTxId &+ 1 // Increment with overflow

        log.debug("Sending message: %{public}@ (TxId: %d)", String(describing: message), currentTxId - 1)

        // Send packets via PeripheralManager
        var sendResult: SendMessageResult?
        peripheralManager.perform { manager in
            sendResult = manager.sendMessagePackets(wrapper.packets)
        }

        // Handle send errors
        switch sendResult {
        case .unsentWithError(let error):
            log.error("Failed to send message: %{public}@", String(describing: error))
            throw error
        case .sentWithError(let error):
            log.error("Message sent but pump returned error: %{public}@", String(describing: error))
            throw error
        case .sentWithAcknowledgment:
            log.debug("Message sent successfully")
        case .none:
            log.error("No send result received")
            throw PumpCommError.noResponse
        }

        // Read response packet
        var responseData: Data?
        peripheralManager.perform { manager in
            responseData = try? manager.readMessagePacket()
        }

        guard let data = responseData else {
            log.error("No response data received")
            throw PumpCommError.noResponse
        }

        log.debug("Received response: %{public}@ bytes", String(describing: data.count))

        // Parse response using BTResponseParser
        let characteristicUUID = type(of: message).props.characteristic.cbUUID
        guard let pumpResponse = BTResponseParser.parse(wrapper: wrapper,
                                                        output: data,
                                                        characteristic: characteristicUUID) else {
            log.error("Failed to parse response")
            throw PumpCommError.other
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
