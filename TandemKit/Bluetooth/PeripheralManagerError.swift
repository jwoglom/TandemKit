//
//  PeripheralManagerError.swift
//  TandemKit
//
//  Created by James Woglom on 1/8/25.
//
//  RileyLinkBLEKit:
//  Copyright © 2017 Pete Schwamb. All rights reserved.

import CoreBluetooth


enum PeripheralManagerError: Error {
    case cbPeripheralError(Error)
    case notReady
    case busy
    case timeout([PeripheralManager.CommandCondition])
    case emptyValue
    case unknownCharacteristic(CBUUID)
    case unknownService(CBUUID)
}


extension PeripheralManagerError {
    public var errorDescription: String? {
        switch self {
        case .cbPeripheralError(let error):
            return error.localizedDescription
        case .notReady:
            return "Not connected"
        case .busy:
            return "Busy"
        case .timeout:
            return "Timeout"
        case .emptyValue:
            return "Characteristic value was empty"
        case .unknownCharacteristic(let cbuuid):
            return String(format: "Unknown characteristic: %@", cbuuid.uuidString)
        case .unknownService(let cbuuid):
            return String(format: "Unknown service: %@", cbuuid.uuidString)
        }
    }
}
