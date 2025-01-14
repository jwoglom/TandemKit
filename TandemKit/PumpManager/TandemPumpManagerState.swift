//
//  TandemPumpManagerState.swift
//  TandemKit
//
//  Created by James Woglom on 1/5/25.
//

import LoopKit

public struct TandemPumpManagerState: RawRepresentable, Equatable {
    public typealias RawValue = PumpManager.RawStateValue
    
    public static let version = 1
    
    public var pumpState: PumpState?

    public init(pumpState: PumpState?) {
        self.pumpState = pumpState
    }
    
    public init?(rawValue: RawValue) {
        
        guard let version = rawValue["version"] as? Int else {
            return nil
        }
        
        let pumpState: PumpState?
        if let pumpStateRaw = rawValue["pumpState"] as? PumpState.RawValue {
            pumpState = PumpState(rawValue: pumpStateRaw)
        } else {
            pumpState = nil
        }
        
        self.init(
            pumpState: pumpState
        )
    }
    
    public var rawValue: RawValue {
        var value: [String : Any] = [
            "version": TandemPumpManagerState.version,
            "pumpState": pumpState?.rawValue as Any
        ]
        return value
    }
}
