//
//  PumpState.swift
//  TandemKit
//
//  Created by James Woglom on 1/5/25.
//

public struct PumpState: RawRepresentable, Equatable, CustomDebugStringConvertible {
    
    public typealias RawValue = [String: Any]
    
    public let address: UInt32
    
    public init(address: UInt32) {
        self.address = address
    }
    
    public init?(rawValue: RawValue) {
        
        guard let address = rawValue["address"] as? UInt32
        else { return nil }
        
        self.address = address
    }
    
    public var rawValue: RawValue {
        var rawValue: RawValue = [
            "address": address,
        ]
        
        return rawValue
    }
    
    public var debugDescription: String {
        return [
            "### PumpState",
            "* address: \(String(format: "%04X", address))"
        ].joined(separator: "\n")
    }
}
