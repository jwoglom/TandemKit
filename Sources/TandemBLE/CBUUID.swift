//
//  CBUUID.swift
//  TandemKit
//
//  Created by James Woglom on 1/13/25.
//
import CoreBluetooth
import TandemCore

// MARK: - CBUUID definition

protocol CBUUIDRawValue: RawRepresentable {}
extension CBUUIDRawValue where RawValue == String {
    var cbUUID: CBUUID {
        #if os(Linux)
            return CBUUID(uuidString: rawValue)
        #else
            return CBUUID(string: rawValue)
        #endif
    }
}

// MARK: - Discovery helpers.

extension CBPeripheral {
    func servicesToDiscover(from serviceUUIDs: [CBUUID]) -> [CBUUID] {
        let knownServiceUUIDs = services?.compactMap(\.uuid) ?? []
        return serviceUUIDs.filter({ !knownServiceUUIDs.contains($0) })
    }

    func characteristicsToDiscover(from characteristicUUIDs: [CBUUID], for service: CBService) -> [CBUUID] {
        let knownCharacteristicUUIDs = service.characteristics?.compactMap(\.uuid) ?? []
        return characteristicUUIDs.filter({ !knownCharacteristicUUIDs.contains($0) })
    }

    func getAuthorizationCharacteristic() -> CBCharacteristic? {
        guard let service = services?.itemWithUUID(ServiceUUID.PUMP_SERVICE.cbUUID) else {
            return nil
        }

        return service.characteristics?.itemWithUUID(CharacteristicUUID.AUTHORIZATION_CHARACTERISTICS.cbUUID)
    }

    func getControlCharacteristic() -> CBCharacteristic? {
        guard let service = services?.itemWithUUID(ServiceUUID.PUMP_SERVICE.cbUUID) else {
            return nil
        }

        return service.characteristics?.itemWithUUID(CharacteristicUUID.CONTROL_CHARACTERISTICS.cbUUID)
    }

    func getControlStreamCharacteristic() -> CBCharacteristic? {
        guard let service = services?.itemWithUUID(ServiceUUID.PUMP_SERVICE.cbUUID) else {
            return nil
        }

        return service.characteristics?.itemWithUUID(CharacteristicUUID.CONTROL_STREAM_CHARACTERISTICS.cbUUID)
    }

    func getCurrentStatusCharacteristic() -> CBCharacteristic? {
        guard let service = services?.itemWithUUID(ServiceUUID.PUMP_SERVICE.cbUUID) else {
            return nil
        }

        return service.characteristics?.itemWithUUID(CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS.cbUUID)
    }

    func getHistoryLogCharacteristic() -> CBCharacteristic? {
        guard let service = services?.itemWithUUID(ServiceUUID.PUMP_SERVICE.cbUUID) else {
            return nil
        }

        return service.characteristics?.itemWithUUID(CharacteristicUUID.HISTORY_LOG_CHARACTERISTICS.cbUUID)
    }

    func getQualifyingEventsCharacteristic() -> CBCharacteristic? {
        guard let service = services?.itemWithUUID(ServiceUUID.PUMP_SERVICE.cbUUID) else {
            return nil
        }

        return service.characteristics?.itemWithUUID(CharacteristicUUID.QUALIFYING_EVENTS_CHARACTERISTICS.cbUUID)
    }

    func getServiceChangedCharacteristic() -> CBCharacteristic? {
        guard let service = services?.itemWithUUID(ServiceUUID.GENERIC_ATTRIBUTE_SERVICE.cbUUID) else {
            return nil
        }

        return service.characteristics?.itemWithUUID(CharacteristicUUID.SERVICE_CHANGED.cbUUID)
    }

    func getManufacturerNameCharacteristic() -> CBCharacteristic? {
        guard let service = services?.itemWithUUID(ServiceUUID.DIS_SERVICE.cbUUID) else {
            return nil
        }

        return service.characteristics?.itemWithUUID(DeviceInformationCharacteristicUUID.manufacturerName.cbUUID)
    }

    func getModelNumberCharacteristic() -> CBCharacteristic? {
        guard let service = services?.itemWithUUID(ServiceUUID.DIS_SERVICE.cbUUID) else {
            return nil
        }

        return service.characteristics?.itemWithUUID(DeviceInformationCharacteristicUUID.modelNumber.cbUUID)
    }

    func characteristic(for uuid: CharacteristicUUID) -> CBCharacteristic? {
        switch uuid {
        case .AUTHORIZATION_CHARACTERISTICS:
            return getAuthorizationCharacteristic()
        case .CONTROL_CHARACTERISTICS:
            return getControlCharacteristic()
        case .CONTROL_STREAM_CHARACTERISTICS:
            return getControlStreamCharacteristic()
        case .CURRENT_STATUS_CHARACTERISTICS:
            return getCurrentStatusCharacteristic()
        case .HISTORY_LOG_CHARACTERISTICS:
            return getHistoryLogCharacteristic()
        case .QUALIFYING_EVENTS_CHARACTERISTICS:
            return getQualifyingEventsCharacteristic()
        case .SERVICE_CHANGED:
            return getServiceChangedCharacteristic()
        case .DIS_MANUFACTURER_NAME:
            return getManufacturerNameCharacteristic()
        case .DIS_MODEL_NUMBER:
            return getModelNumberCharacteristic()
        }
    }
}

extension Collection where Element: CBAttribute {
    func itemWithUUID(_ uuid: CBUUID) -> Element? {
        for attribute in self {
            if attribute.uuid == uuid {
                return attribute
            }
        }

        return nil
    }
}
