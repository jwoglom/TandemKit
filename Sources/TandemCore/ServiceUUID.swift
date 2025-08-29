//
//  ServiceUUID.swift
//  TandemKit
//
//  Created by James Woglom on 1/13/25.
//

import CoreBluetooth

public enum ServiceUUID: String, Sendable {
    // All pump operations
    case PUMP_SERVICE = "0000fdfb-0000-1000-8000-00805f9b34fb"

    // Bluetooth Device Information service (DIS)
    case DIS_SERVICE = "0000180A-0000-1000-8000-00805f9b34fb"

    // Generic Access service
    case GENERIC_ACCESS_SERVICE = "00001800-0000-1000-8000-00805f9b34fb"

    // Generic Attribute service
    case GENERIC_ATTRIBUTE_SERVICE = "00001801-0000-1000-8000-00805f9b34fb"
}

public let AllServiceUUIDs: [ServiceUUID] = [
    .PUMP_SERVICE,
    .DIS_SERVICE,
    .GENERIC_ACCESS_SERVICE,
    .GENERIC_ATTRIBUTE_SERVICE
]

public extension ServiceUUID {
    var cbUUID: CBUUID { CBUUID(uuidString: rawValue) }
}
