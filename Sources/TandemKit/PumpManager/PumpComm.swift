//
//  PumpComm.swift
//  TandemKit
//
//  Created by James Woglom on 1/5/25.
//
//  Basis: OmniBLE PumpComms.swift

import Foundation
import LoopKit
import TandemCore
#if canImport(os)
import os
#endif

public protocol PumpCommDelegate: AnyObject {
    func pumpComm(_ pumpComms: PumpComm, didChange pumpState: PumpState)
    func pumpComm(_ pumpComms: PumpComm,
                  didReceive message: Message,
                  metadata: MessageMetadata?,
                  characteristic: CharacteristicUUID,
                  txId: UInt8)
}


public class PumpComm: CustomDebugStringConvertible {

    var manager: Any? // TODO: Replace with actual PeripheralManager type when available

    public weak var delegate: PumpCommDelegate?

    public let log = OSLog(category: "PumpComm")

    private var session: PumpCommSession?

    // Only valid to access on the session serial queue
    private var pumpState: PumpState? {
        didSet {
            if let newValue = pumpState, newValue != oldValue {
                delegate?.pumpComm(self, didChange: newValue)
            }
        }
    }
    
    public var isDevicePaired: Bool {
        get {
            return self.pumpState?.derivedSecret != nil
        }
    }

    public var isAuthenticated: Bool {
        get {
            return self.pumpState?.derivedSecret != nil
        }
    }
    
    // TODO(jwoglom): device name or PIN?
    public init(pumpState: PumpState?) {
        self.delegate = nil

        let initialState = pumpState ?? PumpState()
        self.pumpState = pumpState ?? initialState
        self.session = PumpCommSession(pumpState: initialState, delegate: self)
    }

#if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
    public func pair(transport: PumpMessageTransport, pairingCode: String) throws {
        let session = ensureSession()
        log.debug("PumpComm pair started")
        try session.runSynchronously(withName: "Pairing") {
            try session.pair(transport: transport, pairingCode: pairingCode)
        }
        log.debug("PumpComm pair finished")
    }
#endif

    private func ensureSession() -> PumpCommSession {
        if let session = self.session {
            return session
        }

        let state = pumpState ?? PumpState()
        let newSession = PumpCommSession(pumpState: state, delegate: self)
        self.session = newSession
        self.pumpState = state
        return newSession
    }

    func getSession() -> PumpCommSession {
        return ensureSession()
    }

    /// Send a message to the pump and receive a response.
    ///
    /// This is a low-level method that sends a message through the transport layer
    /// and returns the response. The transport layer handles packet assembly, HMAC,
    /// CRC, and BLE communication.
    ///
    /// - Parameters:
    ///   - transport: The message transport to use (usually PeripheralManagerTransport)
    ///   - message: The message to send
    /// - Returns: The response message from the pump
    /// - Throws: PumpCommError if communication fails or response is invalid
    public func sendMessage(transport: PumpMessageTransport, message: Message) throws -> Message {
        log.debug("sendMessage: attempting to send %@", String(describing: message))

        do {
            let response = try transport.sendMessage(message)
            log.debug("sendMessage: received response %@", String(describing: response))

            // Check if the response indicates an error condition
            // Note: Different message types may have different error indicators
            // For now, we just return the response and let the caller handle it

            return response
        } catch let error as PumpCommError {
            log.error("sendMessage pump communication error: %{public}@", String(describing: error))
            throw error
        } catch {
            log.error("sendMessage unexpected error: %{public}@", String(describing: error))
            throw PumpCommError.other
        }
    }

    /// Send a message and expect a specific response type.
    ///
    /// This is a convenience method that sends a message and automatically casts
    /// the response to the expected type.
    ///
    /// - Parameters:
    ///   - transport: The message transport to use
    ///   - message: The message to send
    ///   - expectedType: The expected response type
    /// - Returns: The response message cast to the expected type
    /// - Throws: PumpCommError if communication fails or response type doesn't match
    public func sendMessage<T: Message>(transport: PumpMessageTransport, message: Message, expecting expectedType: T.Type) throws -> T {
        let response = try sendMessage(transport: transport, message: message)

        guard let typedResponse = response as? T else {
            log.error("sendMessage unexpected response type: expected %@, got %@",
                     String(describing: expectedType),
                     String(describing: type(of: response)))
            throw PumpCommError.errorResponse(response: response)
        }

        return typedResponse
    }


    // MARK: - CustomDebugStringConvertible
    
    public var debugDescription: String {
        return [
            "## PumpComm",
            "pumpState: \(String(reflecting: pumpState))",
            "delegate: \(String(describing: delegate != nil))",
            ""
        ].joined(separator: "\n")
    }

}

extension PumpComm: PumpCommSessionDelegate {
    public func pumpCommSession(_ pumpCommSession: PumpCommSession, didChange state: PumpState) {
        pumpCommSession.assertOnSessionQueue()
        self.pumpState = state
    }

    public func pumpCommSession(_ pumpCommSession: PumpCommSession,
                                didReceive message: Message,
                                metadata: MessageMetadata?,
                                characteristic: CharacteristicUUID,
                                txId: UInt8) {
        pumpCommSession.assertOnSessionQueue()
        delegate?.pumpComm(self,
                           didReceive: message,
                           metadata: metadata,
                           characteristic: characteristic,
                           txId: txId)
    }
}
