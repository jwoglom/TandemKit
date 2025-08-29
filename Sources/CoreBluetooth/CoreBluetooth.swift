//
//  CoreBluetooth.swift
//  TandemKit
//
//  Minimal stand‑in for Apple's CoreBluetooth when building on Linux,
//  backed by the PureSwift Bluetooth stack.
//

import Bluetooth
import Foundation
import Dispatch

public typealias CBUUID = BluetoothUUID

public enum CBManagerState: Int {
    case unknown
    case resetting
    case unsupported
    case unauthorized
    case poweredOff
    case poweredOn
}

public protocol CBCentralManagerDelegate: AnyObject {
    func centralManagerDidUpdateState(_ central: CBCentralManager)
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber)
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral)
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?)
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?)
}

public protocol CBPeripheralDelegate: AnyObject {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?)
}

public protocol CBAttribute { var uuid: CBUUID { get } }

public class CBCharacteristic: CBAttribute {
    public let uuid: CBUUID
    public var value: Data?
    public var isNotifying: Bool = false
    public init(uuid: CBUUID, value: Data? = nil) {
        self.uuid = uuid
        self.value = value
    }
}

public class CBService: CBAttribute {
    public let uuid: CBUUID
    public var characteristics: [CBCharacteristic]?
    public init(uuid: CBUUID, characteristics: [CBCharacteristic]? = nil) {
        self.uuid = uuid
        self.characteristics = characteristics
    }
}

public enum CBCharacteristicWriteType {
    case withResponse
    case withoutResponse
}

public class CBPeripheral {
    public let identifier: UUID
    public var services: [CBService]?
    public weak var delegate: CBPeripheralDelegate?
    public enum State { case disconnected, connecting, connected }
    public var state: State = .disconnected

    public init(identifier: UUID) {
        self.identifier = identifier
    }

    public func discoverServices(_ serviceUUIDs: [CBUUID]?) { }
    public func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]?, for service: CBService) { }
    public func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic) { }
    public func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) { }
    public func readRSSI() { }
    public func readValue(for characteristic: CBCharacteristic) { }
}

public class CBCentralManager {
    public weak var delegate: CBCentralManagerDelegate?
    public private(set) var isScanning: Bool = false

    public var state: CBManagerState = .unknown

    public init(delegate: CBCentralManagerDelegate?, queue: DispatchQueue?) {
        self.delegate = delegate
        delegate?.centralManagerDidUpdateState(self)
    }

    public func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]? = nil) {
        isScanning = true
    }

    public func stopScan() { isScanning = false }

    public func connect(_ peripheral: CBPeripheral, options: [String: Any]? = nil) { }

    public func cancelPeripheralConnection(_ peripheral: CBPeripheral) { }

    public func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [CBPeripheral] { return [] }

    public func retrieveConnectedPeripherals(withServices serviceUUIDs: [CBUUID]) -> [CBPeripheral] { return [] }
}

