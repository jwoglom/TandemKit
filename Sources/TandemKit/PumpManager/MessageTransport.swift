//
//  MessageTransport.swift
//  TandemKit
//
//  Created by James Woglom on 1/13/25.
//
//  Basis: OmniBLE/MessageTransport/MessageTransport.swift
//  Created by Pete Schwamb on 8/5/18.
//  Copyright © 2021 LoopKit Authors. All rights reserved.

import Foundation

protocol MessageLogger: AnyObject {
    // Comms logging
    func didSend(_ message: Data)
    func didReceive(_ message: Data)
    func didError(_ message: String)
}

public struct MessageTransportState: Equatable, RawRepresentable {
    public typealias RawValue = [String: Any]

    public var txId: UInt8
    public var authenticationKey: Data?
    public var timeSinceReset: UInt32?
    
    init(txId: UInt8, authenticationKey: Data?, timeSinceReset: UInt32?) {
        self.txId = txId
        self.authenticationKey = authenticationKey
        self.timeSinceReset = timeSinceReset
    }
    
    // RawRepresentable
    public init?(rawValue: RawValue) {
        guard
            let txId = rawValue["txId"] as? UInt8,
            let authenticationKey = rawValue["authenticationKey"] as? Data,
            let timeSinceReset = rawValue["timeSinceReset"] as? UInt32
            else {
                return nil
        }
        self.txId = txId
        self.authenticationKey = authenticationKey
        self.timeSinceReset = timeSinceReset
    }
    
    public var rawValue: RawValue {
        return [
            "txId": txId,
            "authenticationKey": authenticationKey?.hexadecimalString ?? "",
            "timeSinceReset": timeSinceReset ?? 0,
        ]
    }

}

extension MessageTransportState: CustomDebugStringConvertible {
    public var debugDescription: String {
        return [
            "## MessageTransportState",
            "txId: \(txId)",
            "authenticationKey: \(authenticationKey?.hexadecimalString ?? "")",
            "timeSinceReset: \(timeSinceReset ?? 0)",
        ].joined(separator: "\n")
    }
}

protocol MessageTransportDelegate: AnyObject {
    func messageTransport(_ messageTransport: MessageTransport, didUpdate state: MessageTransportState)
}

protocol MessageTransport {
    var delegate: MessageTransportDelegate? { get set }

    func sendMessage(_ message: Message) throws -> Message

    /// Asserts that the caller is currently on the session's queue
    func assertOnSessionQueue()
}

class PumpMessageTransport: MessageTransport {
    private let manager: PeripheralManager

    private let log = OSLog(category: "PumpMessageTransport")
    
    private(set) var state: MessageTransportState {
        didSet {
            self.delegate?.messageTransport(self, didUpdate: state)
        }
    }
    
    private(set) var txId: UInt8 {
        get {
            return state.txId
        }
        set {
            state.txId = newValue
        }
    }
    
    private(set) var authenticationKey: Data? {
        get {
            return state.authenticationKey
        }
        set {
            state.authenticationKey = newValue
        }
    }
    
    
    private(set) var timeSinceReset: UInt32? {
        get {
            return state.timeSinceReset
        }
        set {
            state.timeSinceReset = newValue
        }
    }

    private let pumpSerial: String

    weak var messageLogger: MessageLogger?
    weak var delegate: MessageTransportDelegate?

    private var nonceSeq: UInt32 = 0
    private var messageNumber: UInt32 = 0

    init(manager: PeripheralManager, pumpSerial: String, state: MessageTransportState) {
        self.manager = manager
        self.pumpSerial = pumpSerial
        self.state = state
    }
    
    private func incrementTxId(_ count: UInt8 = 1) {
        txId = ((txId) + count) & 0xff
    }

    /// Sends the given packet set over the pump transport and returns the response
    func sendMessage(_ message: Message) throws -> Message {
        
        guard manager.peripheral.state == .connected else {
            throw PumpCommError.pumpNotConnected
        }

        let packets = Packetize(message: message, authenticationKey: state.authenticationKey, txId: state.txId, timeSinceReset: state.timeSinceReset)
        
        for packet in packets {
            let dataToSend = packet.build
            log.default("SendPacket(Hex): %{public}@", dataToSend.hexadecimalString)
            messageLogger?.didSend(dataToSend)
            
            let writeResult = manager.sendMessagePacket(dataToSend)
            switch writeResult {
            case .sentWithAcknowledgment:
                break;
            case .sentWithError(let error):
                messageLogger?.didError("Unacknowledged message sending command seq:\(message.sequenceNum), error = \(error)")
                throw PumpCommsError.unacknowledgedMessage(sequenceNumber: message.sequenceNum, error: error)
            case .unsentWithError(let error):
                throw PumpCommsError.commsError(error: error)
            }
        }
    }
    
    
    private func readAndAckResponse() throws -> Message {
        // guard let enDecrypt = self.enDecrypt else { throw PumpCommsError.pumpNotConnected }

        let readResponse = try manager.readMessagePacket()
        guard let readMessage = readResponse else {
            throw PumpProtocolError.messageIOException("Could not read response")
        }

        incrementNonceSeq()
        let decrypted = try enDecrypt.decrypt(readMessage, nonceSeq)

        let response = try parseResponse(decrypted: decrypted)

        incrementMsgSeq()
        incrementNonceSeq()
        let ack = try getAck(response: decrypted)
        let ackResult = manager.sendMessagePacket(ack)

        // verify that the pump message number matches the expected value
        guard response.sequenceNum == messageNumber else {
            throw MessageError.invalidSequence
        }

        switch ackResult {
        case .sentWithAcknowledgment:
            break
        case .sentWithError, .unsentWithError:
            // We had a communications error trying to send the response ack to the pump.
            let ackErrStr = String(format: "Send of ack failed: %@", String(describing: ackResult))

            // The original behavior here was to throw for this error which will throw out the verified response
            // for a received pump command which forces the unacknowledged response code to try to resolve any insulin
            // delivery related commands while treating other commands types as failures even though they were received.
            // throw PumpProtocolError.messageIOException(ackErrStr)

            // Since we already have a fully verified response, simply log the ack comms error and return
            // the received response since the pump has already accepted the command and provided its response.
            // This results in less bogus failures on successfully received and handled pump commands and
            // could result in a failure trying to send the next pump command but with less ill side effects.
            log.error("%@, but still using validated response %@", ackErrStr, String(describing: response))
        }

        return response
    }
    
    private func parseResponse(decrypted: MessagePacket) throws -> Message {

        let data = try StringLengthPrefixEncoding.parseKeys([RESPONSE_PREFIX], decrypted.payload)[0]

        // Dash pumps generate a CRC16 for messages, but the actual algorithm is not understood and doesn't match the CRC16
        // that the pump enforces for incoming command messages. The Dash PDM explicitly ignores the CRC16 for incoming messages,
        // so we ignore them as well and rely on higher level BLE & Dash message data checking to provide data corruption protection.
        let response = try Message(encodedData: data, checkCRC: false)

        log.default("Recv(Hex): %{public}@", data.hexadecimalString)
        messageLogger?.didReceive(data)

        return response
    }
    
    private func getAck(response: MessagePacket) throws -> MessagePacket {
        guard let enDecrypt = self.enDecrypt else { throw PumpCommsError.pumpNotConnected }

        let ackNumber = (UInt(response.sequenceNumber) + 1) & 0xff
        let msg = MessagePacket(
            type: MessageType.ENCRYPTED,
            source: response.destination.toUInt32(),
            destination: response.source.toUInt32(),
            payload: Data(),
            sequenceNumber: UInt8(msgSeq),
            ack: true,
            ackNumber: UInt8(ackNumber),
            eqos: 0
        )
        return try enDecrypt.encrypt(msg, nonceSeq)
    }
    
    func assertOnSessionQueue() {
        dispatchPrecondition(condition: .onQueue(manager.queue))
    }
}

extension PumpMessageTransport: CustomDebugStringConvertible {
    public var debugDescription: String {
        return [
            "## PumpMessageTransport",
            "eapSeq: \(eapSeq)",
            "msgSeq: \(msgSeq)",
            "nonceSeq: \(nonceSeq)",
            "messageNumber: \(messageNumber)",
        ].joined(separator: "\n")
    }
}

