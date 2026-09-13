import CoreBluetooth
import Foundation

/// Production `PumpCentral`: owns the `CBCentralManager`, is its delegate, and forwards everything
/// keyed by UUID. This is the only file that should touch CoreBluetooth beyond `CBUUID` and
/// `CBManagerState`.
final class CoreBluetoothCentral: NSObject, PumpCentral {
    private let logger = TandemLogger(category: "CoreBluetoothCentral")
    private let queue: DispatchQueue
    private var manager: CBCentralManager!

    // The manager is created before the driver can set `delegate`, and CoreBluetooth posts its
    // first state update straight away. If it lands first, it is replayed when the delegate
    // arrives, so the driver never misses `poweredOn`. Only touched on `queue`.
    private var undeliveredStateUpdate = false

    private let lock = NSLock()
    private weak var _delegate: PumpCentralDelegate?
    // One wrapper per identifier: CoreBluetooth may hand out several CBPeripheral instances for
    // the same pump, and the driver compares and caches by object.
    private var peripherals: [UUID: CoreBluetoothPeripheral] = [:]

    init(queue: DispatchQueue = DispatchQueue(label: "com.jwoglom.TandemKit.bluetoothManagerQueue")) {
        self.queue = queue
        super.init()
        queue.sync {
            manager = CBCentralManager(delegate: self, queue: queue)
        }
    }

    var delegate: PumpCentralDelegate? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _delegate
        }
        set {
            lock.lock()
            _delegate = newValue
            lock.unlock()
            queue.async {
                guard self.undeliveredStateUpdate, let delegate = self.delegate else {
                    return
                }
                self.undeliveredStateUpdate = false
                delegate.centralDidUpdateState(self)
            }
        }
    }

    var state: CBManagerState { manager.state }
    var isScanning: Bool { manager.isScanning }

    func scanForPeripherals(withServices services: [CBUUID], allowDuplicates: Bool) {
        manager.scanForPeripherals(
            withServices: services,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: allowDuplicates]
        )
    }

    func stopScan() {
        manager.stopScan()
    }

    func connect(_ peripheral: PumpPeripheral) {
        guard let wrapped = peripheral as? CoreBluetoothPeripheral else {
            logger.error("connect called with a non-CoreBluetooth peripheral: \(peripheral.identifier)")
            return
        }
        manager.connect(wrapped.cbPeripheral)
    }

    func cancelPeripheralConnection(_ peripheral: PumpPeripheral) {
        guard let wrapped = peripheral as? CoreBluetoothPeripheral else {
            return
        }
        manager.cancelPeripheralConnection(wrapped.cbPeripheral)
    }

    func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [PumpPeripheral] {
        manager.retrievePeripherals(withIdentifiers: identifiers).map(wrap)
    }

    func retrieveConnectedPeripherals(withServices services: [CBUUID]) -> [PumpPeripheral] {
        manager.retrieveConnectedPeripherals(withServices: services).map(wrap)
    }

    private func wrap(_ cbPeripheral: CBPeripheral) -> CoreBluetoothPeripheral {
        lock.lock()
        defer { lock.unlock() }
        if let existing = peripherals[cbPeripheral.identifier] {
            existing.adopt(cbPeripheral)
            return existing
        }
        let wrapper = CoreBluetoothPeripheral(cbPeripheral)
        peripherals[cbPeripheral.identifier] = wrapper
        return wrapper
    }
}

extension CoreBluetoothCentral: PumpCentralLatencyControl {
    func requestLowLatency(for peripheral: PumpPeripheral) {
        #if canImport(ObjectiveC)
        guard let wrapped = peripheral as? CoreBluetoothPeripheral else {
            return
        }
        let selector = NSSelectorFromString("setDesiredConnectionLatency:forPeripheral:")
        if manager.responds(to: selector) {
            let latencyValue = NSNumber(value: 0) // CBPeripheralConnectionLatency.low
            manager.perform(selector, with: latencyValue, with: wrapped.cbPeripheral)
            logger.info("connection priority set -> CBPeripheralConnectionLatency.low")
        } else {
            logger.warning("central manager does not support connection latency adjustment")
        }
        #endif
    }
}

extension CoreBluetoothCentral: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_: CBCentralManager) {
        guard let delegate else {
            undeliveredStateUpdate = true
            return
        }
        delegate.centralDidUpdateState(self)
    }

    func centralManager(
        _: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        delegate?.central(self, didDiscover: wrap(peripheral), advertisementData: advertisementData, rssi: RSSI)
    }

    func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        delegate?.central(self, didConnect: wrap(peripheral))
    }

    func centralManager(_: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        delegate?.central(self, didDisconnect: wrap(peripheral), error: error)
    }

    func centralManager(_: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        delegate?.central(self, didFailToConnect: wrap(peripheral), error: error)
    }
}

/// Wraps one `CBPeripheral`, resolving `CBCharacteristic` handles from UUIDs so the driver never
/// holds one. Delegate callbacks are forwarded with the characteristic's UUID and value.
final class CoreBluetoothPeripheral: NSObject, PumpPeripheral {
    private let logger = TandemLogger(category: "CoreBluetoothPeripheral")
    private let lock = NSLock()
    private var _cbPeripheral: CBPeripheral
    private weak var _delegate: PumpPeripheralDelegate?

    var cbPeripheral: CBPeripheral {
        lock.lock()
        defer { lock.unlock() }
        return _cbPeripheral
    }

    init(_ cbPeripheral: CBPeripheral) {
        _cbPeripheral = cbPeripheral
        super.init()
        cbPeripheral.delegate = self
    }

    /// Takes over a fresh CBPeripheral instance for the same identifier, so callbacks keep flowing
    /// to this wrapper whichever instance CoreBluetooth used.
    func adopt(_ cbPeripheral: CBPeripheral) {
        lock.lock()
        defer { lock.unlock() }
        guard cbPeripheral !== _cbPeripheral else {
            return
        }
        _cbPeripheral = cbPeripheral
        cbPeripheral.delegate = self
    }

    var identifier: UUID { cbPeripheral.identifier }
    var name: String? { cbPeripheral.name }
    var isConnected: Bool { cbPeripheral.state == .connected }

    var delegate: PumpPeripheralDelegate? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _delegate
        }
        set {
            lock.lock()
            _delegate = newValue
            lock.unlock()
        }
    }

    var discoveredServices: [CBUUID] {
        cbPeripheral.services?.map(\.uuid) ?? []
    }

    func discoverServices(_ services: [CBUUID]) {
        cbPeripheral.discoverServices(services)
    }

    func discoverCharacteristics(_ characteristics: [CBUUID], for service: CBUUID) {
        guard let cbService = cbPeripheral.services?.first(where: { $0.uuid == service }) else {
            logger.error("Failed to find service: \(service.uuidString)")
            return
        }
        cbPeripheral.discoverCharacteristics(characteristics, for: cbService)
    }

    func hasCharacteristic(_ characteristic: CBUUID, in service: CBUUID) -> Bool {
        resolve(characteristic, in: service) != nil
    }

    func readValue(for characteristic: CBUUID, in service: CBUUID) {
        guard let cbCharacteristic = resolve(characteristic, in: service) else {
            return
        }
        cbPeripheral.readValue(for: cbCharacteristic)
    }

    func writeValue(_ data: Data, for characteristic: CBUUID, in service: CBUUID) {
        guard let cbCharacteristic = resolve(characteristic, in: service) else {
            return
        }
        cbPeripheral.writeValue(data, for: cbCharacteristic, type: .withResponse)
    }

    func setNotifyValue(_ enabled: Bool, for characteristic: CBUUID, in service: CBUUID) {
        guard let cbCharacteristic = resolve(characteristic, in: service) else {
            return
        }
        cbPeripheral.setNotifyValue(enabled, for: cbCharacteristic)
    }

    private func resolve(_ characteristic: CBUUID, in service: CBUUID) -> CBCharacteristic? {
        guard let cbService = cbPeripheral.services?.first(where: { $0.uuid == service }) else {
            logger.error("Failed to find service: \(service.uuidString)")
            return nil
        }
        guard let cbCharacteristic = cbService.characteristics?.first(where: { $0.uuid == characteristic }) else {
            logger.error("Failed to find characteristic: \(characteristic.uuidString)")
            return nil
        }
        return cbCharacteristic
    }
}

extension CoreBluetoothPeripheral: CBPeripheralDelegate {
    func peripheral(_: CBPeripheral, didDiscoverServices error: Error?) {
        delegate?.peripheral(self, didDiscoverServices: error)
    }

    func peripheral(_: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        delegate?.peripheral(self, didDiscoverCharacteristicsFor: service.uuid, error: error)
    }

    func peripheral(_: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        delegate?.peripheral(self, didUpdateValueFor: characteristic.uuid, value: characteristic.value, error: error)
    }

    func peripheral(_: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        delegate?.peripheral(self, didWriteValueFor: characteristic.uuid, error: error)
    }

    func peripheral(_: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        delegate?.peripheral(self, didUpdateNotificationStateFor: characteristic.uuid, error: error)
    }
}
