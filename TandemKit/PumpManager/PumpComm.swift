//
//  PumpComm.swift
//  TandemKit
//
//  Created by James Woglom on 1/5/25.
//
//  Basis: OmniBLE PumpComms.swift


import Foundation
import LoopKit
import OSLog


protocol PumpCommDelegate: AnyObject {
    func pumpComm(_ pumpComms: PumpComm, didChange pumpState: PumpState)
}


public class PumpComm: CustomDebugStringConvertible {
    
    var manager: PeripheralManager?
    
    weak var delegate: PumpCommDelegate?
    
    public let log = OSLog(category: "PumpComm")

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
            // return self.pumpState?.ltk != nil && (self.pumpState?.ltk.count ?? 0) > 0
            return false
        }
    }
    
    public var isAuthenticated: Bool {
        get {
            // return self.pumpState?.ltk != nil && (self.pumpState?.ltk.count ?? 0) > 0
            return false
        }
    }
    
    // TODO(jwoglom): device name or PIN?
    init(pumpState: PumpState?) {
        self.pumpState = pumpState
        self.delegate = nil
        
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
