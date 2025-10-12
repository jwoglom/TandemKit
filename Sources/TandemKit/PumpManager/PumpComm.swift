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
    init(pumpState: PumpState?) {
        self.delegate = nil

        let initialState = pumpState ?? PumpState()
        self.pumpState = pumpState ?? initialState
        self.session = PumpCommSession(pumpState: initialState, delegate: self)
    }

#if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
    public func pair(transport: PumpMessageTransport, pairingCode: String) throws {
        let session = ensureSession()
        var pairError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        session.runSession(withName: "Pairing") {
            do {
                try session.pair(transport: transport, pairingCode: pairingCode)
            } catch {
                pairError = error
            }
            semaphore.signal()
        }
        semaphore.wait()
        if let error = pairError {
            throw error
        }
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

    // TODO(jwoglom): Performs pairing and returns (?) ( -> ApiVersionResponse?)
    private func sendMessage(transport: PumpMessageTransport, message: Message) throws {
        log.debug("sendPairMessage: attempting to use PumpMessageTransport %@ to send message %@", String(reflecting: transport), String(reflecting: message))
        let pumpMessageResponse = try transport.sendMessage(message)
        

        // fault -> error?
        // TODO(jwoglom): handle error
//        if let fault = pumpMessageResponse.fault {
//            log.error("sendPairMessage pump fault: %{public}@", String(describing: fault))
//            if let pumpState = self.pumpState, pumpState.fault == nil {
//                self.pumpState!.fault = fault
//            }
//            throw PumpCommError.pumpFault(fault: fault)
//        }

//        guard let versionResponse = pumpMessageResponse.messageBlocks[0] as? ApiVersionResponse else {
//            log.error("sendPairMessage unexpected response: %{public}@", String(describing: pumpMessageResponse))
//            let responseType = pumpMessageResponse.messageBlocks[0].blockType
//            throw PumpCommError.unexpectedResponse(response: responseType)
//        }
//
//        log.debug("sendPairMessage: returning versionResponse %@", String(describing: versionResponse))
//        return versionResponse
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
}
