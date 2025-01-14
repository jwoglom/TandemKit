//
//  ServiceUUID.swift
//  TandemKit
//
//  Created by James Woglom on 1/13/25.
//


enum ServiceUUID: String, CBUUIDRawValue {
    // All pump operations
    case PUMP_SERVICE = "0000fdfb-0000-1000-8000-00805f9b34fb"
    
    // Bluetooth Device Information service (DIS)
    case DIS_SERVICE = "0000180A-0000-1000-8000-00805f9b34fb"

    // Generic Access service
    case GENERIC_ACCESS_SERVICE = "00001800-0000-1000-8000-00805f9b34fb"

    // Generic Attribute service
    case GENERIC_ATTRIBUTE_SERVICE = "00001801-0000-1000-8000-00805f9b34fb"

}

let AllServiceUUIDs = [
    ServiceUUID.PUMP_SERVICE,
    ServiceUUID.DIS_SERVICE,
    ServiceUUID.GENERIC_ACCESS_SERVICE,
    ServiceUUID.GENERIC_ATTRIBUTE_SERVICE
]
