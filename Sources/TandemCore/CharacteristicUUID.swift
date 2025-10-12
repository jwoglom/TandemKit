//
//  CharacteristicUUID.swift
//  TandemKit
//
//  Created by James Woglom on 1/5/25.
//

import CoreBluetooth

public enum CharacteristicUUID: String, Sendable {
    // For reading pump state
    case CURRENT_STATUS_CHARACTERISTICS = "7B83FFF6-9F77-4E5C-8064-AAE2C24838B9"
    case QUALIFYING_EVENTS_CHARACTERISTICS = "7B83FFF7-9F77-4E5C-8064-AAE2C24838B9"
    case HISTORY_LOG_CHARACTERISTICS = "7B83FFF8-9F77-4E5C-8064-AAE2C24838B9"

    // For authentication
    case AUTHORIZATION_CHARACTERISTICS = "7B83FFF9-9F77-4E5C-8064-AAE2C24838B9"

    // For signed messages
    case CONTROL_CHARACTERISTICS = "7B83FFFC-9F77-4E5C-8064-AAE2C24838B9"
    case CONTROL_STREAM_CHARACTERISTICS = "7B83FFFD-9F77-4E5C-8064-AAE2C24838B9"

    // Generic Attribute service
    case SERVICE_CHANGED = "00002A05-0000-1000-8000-00805F9B34FB"
}

public let AllPumpCharacteristicUUIDs: [CharacteristicUUID] = [
    .CURRENT_STATUS_CHARACTERISTICS,
    .QUALIFYING_EVENTS_CHARACTERISTICS,
    .HISTORY_LOG_CHARACTERISTICS,
    .AUTHORIZATION_CHARACTERISTICS,
    .CONTROL_CHARACTERISTICS,
    .CONTROL_STREAM_CHARACTERISTICS
]

public let AllTandemNotificationCharacteristicUUIDs: [CharacteristicUUID] = AllPumpCharacteristicUUIDs

public let TandemNotificationOrder: [CharacteristicUUID] = [
    .AUTHORIZATION_CHARACTERISTICS,
    .CURRENT_STATUS_CHARACTERISTICS,
    .HISTORY_LOG_CHARACTERISTICS,
    .CONTROL_CHARACTERISTICS,
    .CONTROL_STREAM_CHARACTERISTICS,
    .QUALIFYING_EVENTS_CHARACTERISTICS,
    .SERVICE_CHANGED
]

public enum DeviceInformationCharacteristicUUID: String, Sendable {
    case manufacturerName = "00002A29-0000-1000-8000-00805F9B34FB"
    case modelNumber = "00002A24-0000-1000-8000-00805F9B34FB"
}

public let DeviceInformationCharacteristics: [DeviceInformationCharacteristicUUID] = [
    .manufacturerName,
    .modelNumber
]

public extension DeviceInformationCharacteristicUUID {
    var cbUUID: CBUUID {
#if os(Linux)
        return CBUUID(uuidString: rawValue)
#else
        return CBUUID(string: rawValue)
#endif
    }

    var prettyName: String {
        switch self {
        case .manufacturerName: return "ManufacturerName"
        case .modelNumber: return "ModelNumber"
        }
    }
}

public extension CharacteristicUUID {
    var cbUUID: CBUUID {
#if os(Linux)
        return CBUUID(uuidString: rawValue)
#else
        return CBUUID(string: rawValue)
#endif
    }

    var prettyName: String {
        switch self {
        case .CURRENT_STATUS_CHARACTERISTICS: return "CurrentStatus"
        case .QUALIFYING_EVENTS_CHARACTERISTICS: return "QualifyingEvents"
        case .HISTORY_LOG_CHARACTERISTICS: return "HistoryLog"
        case .AUTHORIZATION_CHARACTERISTICS: return "Authorization"
        case .CONTROL_CHARACTERISTICS: return "Control"
        case .CONTROL_STREAM_CHARACTERISTICS: return "ControlStream"
        case .SERVICE_CHANGED: return "ServiceChanged"
        }
    }
}
