import Bluetooth
import Dispatch
import Foundation

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
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    )
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

    public func discoverServices(_: [CBUUID]?) {}
    public func discoverCharacteristics(_: [CBUUID]?, for _: CBService) {}
    public func setNotifyValue(_: Bool, for _: CBCharacteristic) {}
    public func writeValue(_: Data, for _: CBCharacteristic, type _: CBCharacteristicWriteType) {}
    public func readRSSI() {}
    public func readValue(for _: CBCharacteristic) {}
}

public class CBCentralManager {
    public weak var delegate: CBCentralManagerDelegate?
    public private(set) var isScanning: Bool = false

    public var state: CBManagerState = .unknown

    public init(delegate: CBCentralManagerDelegate?, queue _: DispatchQueue?) {
        self.delegate = delegate
        delegate?.centralManagerDidUpdateState(self)
    }

    public func scanForPeripherals(withServices _: [CBUUID]?, options _: [String: Any]? = nil) {
        isScanning = true
    }

    public func stopScan() { isScanning = false }

    public func connect(_: CBPeripheral, options _: [String: Any]? = nil) {}

    public func cancelPeripheralConnection(_: CBPeripheral) {}

    public func retrievePeripherals(withIdentifiers _: [UUID]) -> [CBPeripheral] { [] }

    public func retrieveConnectedPeripherals(withServices _: [CBUUID]) -> [CBPeripheral] { [] }
}

// MARK: - Peripheral Manager (Server/Peripheral Mode)

public enum CBAdvertisementData {
    public static let LocalNameKey = "kCBAdvDataLocalName"
    public static let ServiceUUIDsKey = "kCBAdvDataServiceUUIDs"
}

public struct CBCharacteristicProperties: OptionSet {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let broadcast = CBCharacteristicProperties(rawValue: 0x01)
    public static let read = CBCharacteristicProperties(rawValue: 0x02)
    public static let writeWithoutResponse = CBCharacteristicProperties(rawValue: 0x04)
    public static let write = CBCharacteristicProperties(rawValue: 0x08)
    public static let notify = CBCharacteristicProperties(rawValue: 0x10)
    public static let indicate = CBCharacteristicProperties(rawValue: 0x20)
    public static let authenticatedSignedWrites = CBCharacteristicProperties(rawValue: 0x40)
    public static let extendedProperties = CBCharacteristicProperties(rawValue: 0x80)
    public static let notifyEncryptionRequired = CBCharacteristicProperties(rawValue: 0x100)
    public static let indicateEncryptionRequired = CBCharacteristicProperties(rawValue: 0x200)
}

public struct CBAttributePermissions: OptionSet {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let readable = CBAttributePermissions(rawValue: 0x01)
    public static let writeable = CBAttributePermissions(rawValue: 0x02)
    public static let readEncryptionRequired = CBAttributePermissions(rawValue: 0x04)
    public static let writeEncryptionRequired = CBAttributePermissions(rawValue: 0x08)
}

public protocol CBPeripheralManagerDelegate: AnyObject {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager)
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?)
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?)
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic)
    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    )
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest)
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest])
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager)
}

public class CBCentral {
    public let identifier: UUID
    public var maximumUpdateValueLength: Int { 512 }

    public init(identifier: UUID = UUID()) {
        self.identifier = identifier
    }
}

public class CBATTRequest {
    public let central: CBCentral
    public let characteristic: CBCharacteristic
    public var value: Data?
    public var offset: Int = 0

    public init(central: CBCentral, characteristic: CBCharacteristic, value: Data? = nil, offset: Int = 0) {
        self.central = central
        self.characteristic = characteristic
        self.value = value
        self.offset = offset
    }
}

public enum CBATTError: Int, Error {
    case success = 0x00
    case invalidHandle = 0x01
    case readNotPermitted = 0x02
    case writeNotPermitted = 0x03
    case invalidPdu = 0x04
    case insufficientAuthentication = 0x05
    case requestNotSupported = 0x06
    case invalidOffset = 0x07
    case insufficientAuthorization = 0x08
    case prepareQueueFull = 0x09
    case attributeNotFound = 0x0A
    case attributeNotLong = 0x0B
    case insufficientEncryptionKeySize = 0x0C
    case invalidAttributeValueLength = 0x0D
    case unlikelyError = 0x0E
    case insufficientEncryption = 0x0F
    case unsupportedGroupType = 0x10
    case insufficientResources = 0x11
}

public class CBMutableCharacteristic: CBCharacteristic {
    public var properties: CBCharacteristicProperties
    public var permissions: CBAttributePermissions
    public var subscribedCentrals: [CBCentral]?

    public init(type uuid: CBUUID, properties: CBCharacteristicProperties, value: Data?, permissions: CBAttributePermissions) {
        self.properties = properties
        self.permissions = permissions
        super.init(uuid: uuid, value: value)
    }
}

public class CBMutableService: CBService {
    public init(type uuid: CBUUID, primary _: Bool) {
        super.init(uuid: uuid, characteristics: nil)
    }
}

public class CBPeripheralManager {
    public weak var delegate: CBPeripheralManagerDelegate?
    public var state: CBManagerState = .unknown
    public private(set) var isAdvertising: Bool = false

    private var services: [CBMutableService] = []
    private var connectedCentrals: [CBCentral] = []
    private let queue: DispatchQueue?

    public init(delegate: CBPeripheralManagerDelegate?, queue: DispatchQueue?, options _: [String: Any]? = nil) {
        self.delegate = delegate
        self.queue = queue

        // Simulate state becoming powered on
        DispatchQueue.main.async {
            self.state = .poweredOn
            delegate?.peripheralManagerDidUpdateState(self)
        }
    }

    public func add(_ service: CBMutableService) {
        services.append(service)

        DispatchQueue.main.async {
            self.delegate?.peripheralManager(self, didAdd: service, error: nil)
        }
    }

    public func remove(_ service: CBMutableService) {
        services.removeAll { $0.uuid == service.uuid }
    }

    public func removeAllServices() {
        services.removeAll()
    }

    public func startAdvertising(_: [String: Any]?) {
        isAdvertising = true

        DispatchQueue.main.async {
            self.delegate?.peripheralManagerDidStartAdvertising(self, error: nil)
        }
    }

    public func stopAdvertising() {
        isAdvertising = false
    }

    public func respond(to _: CBATTRequest, withResult _: CBATTError) {
        // In a real implementation, this would send the response back to the central
        // For the shim, this is a no-op
    }

    public func updateValue(_: Data, for _: CBMutableCharacteristic, onSubscribedCentrals _: [CBCentral]?) -> Bool {
        // In a real implementation, this would send a notification to subscribed centrals
        // For the shim, we'll simulate success
        true
    }

    // Helper methods for simulator to inject events
    func simulateSubscription(central: CBCentral, to characteristic: CBCharacteristic) {
        if !connectedCentrals.contains(where: { $0.identifier == central.identifier }) {
            connectedCentrals.append(central)
        }

        delegate?.peripheralManager(self, central: central, didSubscribeTo: characteristic)
    }

    func simulateUnsubscription(central: CBCentral, from characteristic: CBCharacteristic) {
        delegate?.peripheralManager(self, central: central, didUnsubscribeFrom: characteristic)
    }

    func simulateWriteRequest(central: CBCentral, characteristic: CBCharacteristic, value: Data) {
        let request = CBATTRequest(central: central, characteristic: characteristic, value: value)
        delegate?.peripheralManager(self, didReceiveWrite: [request])
    }

    func simulateReadRequest(central: CBCentral, characteristic: CBCharacteristic) {
        let request = CBATTRequest(central: central, characteristic: characteristic)
        delegate?.peripheralManager(self, didReceiveRead: request)
    }
}
