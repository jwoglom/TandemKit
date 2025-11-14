import Foundation
import TandemCore
import Logging
import CoreBluetooth

/// BLE peripheral transport for simulating a Tandem pump
/// Works on both macOS (native CoreBluetooth) and Linux (custom shim)
class BLEPeripheralTransport: NSObject, SimulatorTransport {
    private let logger = Logger(label: "TandemSimulator.BLEPeripheralTransport")

    // BLE peripheral manager
    private var peripheralManager: CBPeripheralManager?

    // GATT service and characteristics
    private var tandemService: CBMutableService?
    private var characteristics: [CharacteristicUUID: CBMutableCharacteristic] = [:]

    // Packet queues for incoming data (from central to peripheral)
    private var receiveQueues: [CharacteristicUUID: PacketQueue] = [:]

    // Connection state
    private let lock = NSLock()
    private var _isConnected = false
    private var subscribedCentral: CBCentral?

    // Configuration
    private let deviceName: String
    private let serviceUUID: CBUUID

    var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isConnected
    }

    init(deviceName: String = "Tandem t:slim X2") {
        self.deviceName = deviceName
        // Tandem pump service UUID
        self.serviceUUID = CBUUID(string: "7B83FFF0-9F77-4E5C-8064-AAE2C24838B9")

        super.init()

        // Initialize receive queues for all characteristics
        let allCharacteristics: [CharacteristicUUID] = [
            .AUTHORIZATION_CHARACTERISTICS,
            .CURRENT_STATUS_CHARACTERISTICS,
            .HISTORY_LOG_CHARACTERISTICS,
            .QUALIFYING_EVENTS_CHARACTERISTICS,
            .CONTROL_CHARACTERISTICS,
            .CONTROL_STREAM_CHARACTERISTICS
        ]

        for char in allCharacteristics {
            receiveQueues[char] = PacketQueue()
        }
    }

    // MARK: - SimulatorTransport

    func start() async throws {
        logger.info("BLE peripheral transport starting")

        return try await withCheckedThrowingContinuation { continuation in
            // Create peripheral manager
            peripheralManager = CBPeripheralManager(
                delegate: self,
                queue: DispatchQueue.main,
                options: nil
            )

            // Store continuation to resume when ready
            self.startContinuation = continuation
        }
    }

    private var startContinuation: CheckedContinuation<Void, Error>?

    private func setupService() {
        guard let peripheralManager = peripheralManager else {
            logger.error("Peripheral manager not initialized")
            return
        }

        logger.info("Setting up GATT service and characteristics")

        // Create mutable characteristics for all Tandem characteristics
        let characteristicConfigs: [(CharacteristicUUID, CBCharacteristicProperties, CBAttributePermissions)] = [
            (.AUTHORIZATION_CHARACTERISTICS, [.write, .notify], [.writeable]),
            (.CURRENT_STATUS_CHARACTERISTICS, [.write, .notify], [.writeable]),
            (.HISTORY_LOG_CHARACTERISTICS, [.write, .notify], [.writeable]),
            (.QUALIFYING_EVENTS_CHARACTERISTICS, [.write, .notify], [.writeable]),
            (.CONTROL_CHARACTERISTICS, [.write, .notify], [.writeable]),
            (.CONTROL_STREAM_CHARACTERISTICS, [.write, .notify], [.writeable])
        ]

        var mutableCharacteristics: [CBMutableCharacteristic] = []

        for (charUUID, properties, permissions) in characteristicConfigs {
            let characteristic = CBMutableCharacteristic(
                type: CBUUID(string: charUUID.rawValue),
                properties: properties,
                value: nil, // Dynamic value
                permissions: permissions
            )

            characteristics[charUUID] = characteristic
            mutableCharacteristics.append(characteristic)

            logger.debug("Created characteristic: \(charUUID.prettyName)")
        }

        // Create service with characteristics
        tandemService = CBMutableService(type: serviceUUID, primary: true)
        tandemService?.characteristics = mutableCharacteristics

        // Add service to peripheral manager
        peripheralManager.add(tandemService!)
    }

    private func startAdvertising() {
        guard let peripheralManager = peripheralManager else {
            logger.error("Peripheral manager not initialized")
            return
        }

        logger.info("Starting BLE advertising as '\(deviceName)'")

        let advertisementData: [String: Any] = [
            CBAdvertisementDataLocalNameKey: deviceName,
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
        ]

        peripheralManager.startAdvertising(advertisementData)
    }

    func stop() async throws {
        logger.info("BLE peripheral transport stopping")

        lock.lock()
        _isConnected = false
        subscribedCentral = nil
        lock.unlock()

        // Stop advertising
        peripheralManager?.stopAdvertising()

        // Remove service
        if let service = tandemService {
            peripheralManager?.remove(service)
        }

        // Clear all queues
        for queue in receiveQueues.values {
            queue.clear()
        }

        peripheralManager = nil
        characteristics.removeAll()

        logger.info("BLE peripheral transport stopped")
    }

    func readPacket(for characteristic: CharacteristicUUID, timeout: TimeInterval) async throws -> Data? {
        guard isConnected else {
            throw BLEPeripheralTransportError.notConnected
        }

        guard let queue = receiveQueues[characteristic] else {
            throw BLEPeripheralTransportError.unknownCharacteristic(characteristic)
        }

        return await queue.dequeue(timeout: timeout)
    }

    func writePacket(_ data: Data, to characteristic: CharacteristicUUID) async throws {
        try await notify(data, on: characteristic)
    }

    func notify(_ data: Data, on characteristic: CharacteristicUUID) async throws {
        guard isConnected else {
            throw BLEPeripheralTransportError.notConnected
        }

        guard let mutableChar = characteristics[characteristic] else {
            throw BLEPeripheralTransportError.unknownCharacteristic(characteristic)
        }

        guard let peripheralManager = peripheralManager else {
            throw BLEPeripheralTransportError.peripheralManagerNotInitialized
        }

        logger.debug("Notifying on \(characteristic.prettyName): \(data.hexadecimalString)")

        // Update the characteristic value and notify subscribed centrals
        let success = peripheralManager.updateValue(
            data,
            for: mutableChar,
            onSubscribedCentrals: subscribedCentral.map { [$0] }
        )

        if !success {
            logger.warning("Failed to send notification - queue full, will retry")
            // In a real implementation, we would queue this and retry when ready
            // For now, we'll just log the warning
        }
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BLEPeripheralTransport: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        logger.info("Peripheral manager state changed to: \(peripheral.state.rawValue)")

        switch peripheral.state {
        case .poweredOn:
            logger.info("Bluetooth powered on - setting up service")
            setupService()

        case .poweredOff:
            logger.warning("Bluetooth powered off")
            if let continuation = startContinuation {
                startContinuation = nil
                continuation.resume(throwing: BLEPeripheralTransportError.bluetoothPoweredOff)
            }

        case .unsupported:
            logger.error("Bluetooth not supported on this device")
            if let continuation = startContinuation {
                startContinuation = nil
                continuation.resume(throwing: BLEPeripheralTransportError.bluetoothUnsupported)
            }

        case .unauthorized:
            logger.error("Bluetooth unauthorized")
            if let continuation = startContinuation {
                startContinuation = nil
                continuation.resume(throwing: BLEPeripheralTransportError.bluetoothUnauthorized)
            }

        default:
            logger.info("Bluetooth state: \(peripheral.state.rawValue)")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            logger.error("Failed to add service: \(error.localizedDescription)")
            if let continuation = startContinuation {
                startContinuation = nil
                continuation.resume(throwing: error)
            }
            return
        }

        logger.info("Service added successfully - starting advertising")
        startAdvertising()
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            logger.error("Failed to start advertising: \(error.localizedDescription)")
            if let continuation = startContinuation {
                startContinuation = nil
                continuation.resume(throwing: error)
            }
            return
        }

        logger.info("BLE peripheral is now advertising and ready for connections")

        if let continuation = startContinuation {
            startContinuation = nil
            continuation.resume()
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        logger.info("Central \(central.identifier) subscribed to characteristic: \(characteristic.uuid.uuidString)")

        lock.lock()
        defer { lock.unlock() }

        // Track the connected central
        subscribedCentral = central

        // Check if all required characteristics are subscribed
        // For simplicity, we consider connected if any characteristic is subscribed
        _isConnected = true

        logger.info("BLE peripheral is now connected")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        logger.info("Central \(central.identifier) unsubscribed from characteristic: \(characteristic.uuid.uuidString)")

        lock.lock()
        defer { lock.unlock() }

        // Check if central has unsubscribed from all characteristics
        let stillSubscribed = characteristics.values.contains { char in
            char.subscribedCentrals?.contains(where: { $0.identifier == central.identifier }) ?? false
        }

        if !stillSubscribed {
            _isConnected = false
            subscribedCentral = nil
            logger.info("Central disconnected - no more subscriptions")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        logger.debug("Received \(requests.count) write request(s)")

        for request in requests {
            guard let value = request.value else {
                logger.warning("Write request with no value")
                peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
                continue
            }

            // Find the characteristic UUID
            let charUUIDString = request.characteristic.uuid.uuidString
            guard let charUUID = CharacteristicUUID(rawValue: charUUIDString) else {
                logger.warning("Write to unknown characteristic: \(charUUIDString)")
                peripheral.respond(to: request, withResult: .attributeNotFound)
                continue
            }

            logger.debug("Write to \(charUUID.prettyName): \(value.hexadecimalString)")

            // Enqueue the packet for processing
            if let queue = receiveQueues[charUUID] {
                queue.enqueue(value)
                peripheral.respond(to: request, withResult: .success)
            } else {
                logger.error("No queue for characteristic: \(charUUID.prettyName)")
                peripheral.respond(to: request, withResult: .attributeNotFound)
            }
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        logger.debug("Received read request for characteristic: \(request.characteristic.uuid.uuidString)")

        // Tandem pumps don't support reading characteristics - they only support writes and notifications
        peripheral.respond(to: request, withResult: .readNotPermitted)
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        logger.debug("Peripheral manager is ready to send more notifications")
        // This is called when the notification queue has space available
        // We could use this to retry failed notifications
    }
}

// MARK: - Errors

enum BLEPeripheralTransportError: Error, LocalizedError {
    case notConnected
    case unknownCharacteristic(CharacteristicUUID)
    case peripheralManagerNotInitialized
    case bluetoothPoweredOff
    case bluetoothUnsupported
    case bluetoothUnauthorized

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "BLE peripheral is not connected"
        case .unknownCharacteristic(let char):
            return "Unknown characteristic: \(char.rawValue)"
        case .peripheralManagerNotInitialized:
            return "Peripheral manager not initialized"
        case .bluetoothPoweredOff:
            return "Bluetooth is powered off"
        case .bluetoothUnsupported:
            return "Bluetooth is not supported on this device"
        case .bluetoothUnauthorized:
            return "Bluetooth is not authorized"
        }
    }
}
