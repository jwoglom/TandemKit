//
//  PeripheralManager.swift
//  TandemKit
//
//  Created by James Woglom on 1/8/25.
//
//  RileyLinkBLEKit:
//  Copyright © 2017 LoopKit Authors. All rights reserved.


import CoreBluetooth
import Foundation
import TandemCore
#if canImport(os)
import os
#endif

public class PeripheralManager: NSObject, @unchecked Sendable {

    private let log = OSLog(category: "PeripheralManager")
    private let logger = PumpLogger(label: "TandemBLE.PeripheralManager")

    ///
    /// This is mutable, because CBPeripheral instances can seemingly become invalid, and need to be periodically re-fetched from CBCentralManager
    var peripheral: CBPeripheral {
        didSet {
            guard oldValue !== peripheral else {
                return
            }

            log.error("Replacing peripheral reference %{public}@ -> %{public}@", String(describing: oldValue), String(describing: peripheral))

            oldValue.delegate = nil
            peripheral.delegate = self

            queue.sync {
                self.needsConfiguration = true
            }
        }
    }
    
    var cmdQueue: [BluetoothCmd] = []
    let queueLock = NSCondition()

    var idleStart: Date? = nil

    private var connectionParametersVerified = false
    private var didPerformInitialSetup = false
    private var initialConnectionReady = false
    var subscribedCharacteristicUUIDs = Set<CharacteristicUUID>()
    private(set) var manufacturerName: String?
    private(set) var modelNumber: String?

    var needsReconnection: Bool {
        guard let start = idleStart else { return false }

        return Date().timeIntervalSince(start) > .minutes(2.9)
    }


    /// The dispatch queue used to serialize operations on the peripheral
    let queue = DispatchQueue(label: "com.jwoglom.TandemKit.PeripheralManager.queue", qos: .unspecified)
    let queueSpecificKey = DispatchSpecificKey<Void>()

    private let sessionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.jwoglom.TandemKit.PeripheralManager.sessionQueue"
        queue.maxConcurrentOperationCount = 1

        return queue
    }()

    /// The condition used to signal command completion
    let commandLock = NSCondition()

    /// The required conditions for the operation to complete
    private var commandConditions = [CommandCondition]()

    /// Any error surfaced during the active operation
    private var commandError: Error?

    private(set) weak var central: CBCentralManager?

    let configuration: Configuration

    // Confined to `queue`
    private var needsConfiguration = true

    weak var delegate: PeripheralManagerDelegate?

    init(peripheral: CBPeripheral, configuration: Configuration, centralManager: CBCentralManager) {
        self.peripheral = peripheral
        self.central = centralManager
        self.configuration = configuration

        super.init()

        peripheral.delegate = self

        queue.setSpecific(key: queueSpecificKey, value: ())
        assertConfiguration()
    }

    func logDebug(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.debug(msg)
        log.debug("%{public}@", msg)
    }

    func logInfo(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.info(msg)
        log.default("%{public}@", msg)
    }

    func logWarning(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.warning(msg)
        log.info("%{public}@", msg)
    }

    func logError(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.error(msg)
        log.error("%{public}@", msg)
    }
}


// MARK: - Nested types
extension PeripheralManager {
    struct Configuration {
        var serviceCharacteristics: [CBUUID: [CBUUID]] = [:]
        var notifyingCharacteristics: [CBUUID: [CBUUID]] = [:]
        var valueUpdateMacros: [CBUUID: (_ manager: PeripheralManager) -> Void] = [:]
    }

    enum CommandCondition {
        case notificationStateUpdate(characteristicUUID: CBUUID, enabled: Bool)
        case valueUpdate(characteristic: CBCharacteristic, matching: ((Data?) -> Bool)?)
        case write(characteristic: CBCharacteristic)
        case discoverServices
        case discoverCharacteristicsForService(serviceUUID: CBUUID)
        case connect
    }
}

protocol PeripheralManagerDelegate: AnyObject {
    // Called from the PeripheralManager's queue
    func completeConfiguration(for manager: PeripheralManager) throws
    func peripheralManager(_ manager: PeripheralManager, didIdentifyDevice manufacturer: String, model: String)
}

extension PeripheralManagerDelegate {
    func peripheralManager(_ manager: PeripheralManager, didIdentifyDevice manufacturer: String, model: String) {}
}


// MARK: - Operation sequence management
extension PeripheralManager {


    @discardableResult
    func runConfigured<T>(_ block: (_ manager: PeripheralManager) throws -> T) rethrows -> T {
        dispatchPrecondition(condition: .onQueue(queue))

        if self.needsReconnection {
            self.log.default("Triggering forceful reconnect")
            do {
                try self.reconnect(timeout: 5)
            } catch let error {
                self.log.error("Error while forcing reconnection: %{public}@", String(describing: error))
            }
        }

        if !self.needsConfiguration && self.peripheral.services == nil {
            self.log.error("Configured peripheral has no services. Reconfiguring %{public}@", String(describing: self.peripheral))
        }

        if self.needsConfiguration || self.peripheral.services == nil {
            do {
                self.log.default("Applying configuration")
                try self.applyConfiguration()
                try self.performInitialSetupIfNeeded()

                self.needsConfiguration = false

                if let delegate = self.delegate {
                    try delegate.completeConfiguration(for: self)

                    self.log.default("Delegate configuration notified")
                }

                self.log.default("Peripheral configuration completed")
            } catch let error {
                self.log.error("Error applying peripheral configuration: %{public}@", String(describing: error))
                // Will retry
            }
        }

        return try block(self)
    }

    private func performInitialSetupIfNeeded() throws {
        guard !didPerformInitialSetup else { return }

        logInfo("[PeripheralManager] init step 1: verifying MTU >= 185 and requesting high priority")
        try ensureConnectionParameters()
        logInfo("[PeripheralManager] init step 1 complete")

        logInfo("[PeripheralManager] init step 2: reading Device Information Service manufacturer/model")
        let (manufacturer, model) = try readDeviceInformation()
        manufacturerName = manufacturer
        modelNumber = model
        logInfo("[PeripheralManager] init step 2 complete manufacturer=\(manufacturer) model=\(model)")
        delegate?.peripheralManager(self, didIdentifyDevice: manufacturer, model: model)

        logInfo("[PeripheralManager] init step 3: enabling characteristic notifications")
        try enableNotifications()
        logInfo("[PeripheralManager] init step 3 complete")

        didPerformInitialSetup = true
        logInfo("[PeripheralManager] initialization steps complete")
        markInitializationReady()
    }

    private func ensureConnectionParameters() throws {
        guard !connectionParametersVerified else { return }

        let targetMTU: UInt16 = 185
        let maxWithResponse = peripheral.maximumWriteValueLength(for: .withResponse)
        let maxWithoutResponse = peripheral.maximumWriteValueLength(for: .withoutResponse)

        logDebug("[PeripheralManager]   requested MTU=\(targetMTU) withResponseCapacity=\(maxWithResponse) withoutResponseCapacity=\(maxWithoutResponse)")

        if maxWithResponse < Int(targetMTU - 3) { // Approximate payload length after headers
            logWarning("[PeripheralManager]   MTU verification failed – pump likely not in pairing mode")
            throw PeripheralManagerError.notReady
        }

        logDebug("[PeripheralManager]   MTU verification succeeded")

        if let central = central {
            let selector = NSSelectorFromString("setDesiredConnectionLatency:forPeripheral:")
            if central.responds(to: selector) {
                logDebug("[PeripheralManager]   setting connection priority HIGH")
                let latencyValue = NSNumber(value: 0) // CBPeripheralConnectionLatency.low
                central.perform(selector, with: latencyValue, with: peripheral)
                logDebug("[PeripheralManager]   connection priority set")
            } else {
                logWarning("[PeripheralManager]   central manager does not support connection latency adjustment")
            }
        } else {
            logWarning("[PeripheralManager]   central manager unavailable; skipping priority change")
        }

        connectionParametersVerified = true
    }

    private func markInitializationReady() {
        guard !initialConnectionReady else { return }
        initialConnectionReady = true
        logInfo("[PeripheralManager] initial pump connection established; authentication may proceed")
    }

    private func readDeviceInformation() throws -> (String, String) {
        guard let manufacturerCharacteristic = peripheral.getManufacturerNameCharacteristic() else {
            logWarning("[PeripheralManager]   manufacturer characteristic unavailable")
            throw PeripheralManagerError.notReady
        }

        guard let manufacturerValue = try readValue(for: manufacturerCharacteristic, timeout: TimeInterval.seconds(5)),
              let manufacturer = string(from: manufacturerValue), !manufacturer.isEmpty else {
            logWarning("[PeripheralManager]   manufacturer value empty")
            throw PeripheralManagerError.emptyValue
        }

        guard let modelCharacteristic = peripheral.getModelNumberCharacteristic() else {
            logWarning("[PeripheralManager]   model number characteristic unavailable")
            throw PeripheralManagerError.notReady
        }

        guard let modelValue = try readValue(for: modelCharacteristic, timeout: TimeInterval.seconds(5)),
              let model = string(from: modelValue), !model.isEmpty else {
            logWarning("[PeripheralManager]   model number value empty")
            throw PeripheralManagerError.emptyValue
        }

        return (manufacturer, model)
    }

    private func string(from data: Data) -> String? {
        if let string = String(data: data, encoding: .utf8) {
            let trimSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{0000}"))
            return string.trimmingCharacters(in: trimSet)
        }
        return nil
    }

    func configureAndRun(_ block: @escaping @Sendable (_ manager: PeripheralManager) -> Void) -> @Sendable () -> Void {
        return { self.runConfigured(block) }
    }

    public func perform(_ block: @escaping @Sendable (_ manager: PeripheralManager) -> Void) {
        queue.async {
            self.runConfigured(block)
        }
    }

    func assertConfiguration() {
        if peripheral.state == .connected && central?.state == .poweredOn {
            perform { (_) in
                // Intentionally empty to trigger configuration if necessary
            }
        }
    }

    private func applyConfiguration(discoveryTimeout: TimeInterval = 2) throws {
        try discoverServices(configuration.serviceCharacteristics.keys.map { $0 }, timeout: discoveryTimeout)

        for service in peripheral.services ?? [] {
            log.default("Discovered service: %{public}@", String(describing: service))
            guard let characteristics = configuration.serviceCharacteristics[service.uuid] else {
                // Not all services may have characteristics
                continue
            }
            try discoverCharacteristics(characteristics, for: service, timeout: discoveryTimeout)
        }

    }
}


// MARK: - Synchronous Commands
extension PeripheralManager {
    /// - Throws: PeripheralManagerError
    func runCommand(timeout: TimeInterval, command: () -> Void) throws {
        // Prelude
        dispatchPrecondition(condition: .onQueue(queue))
        guard central?.state == .poweredOn && peripheral.state == .connected else {
            self.log.info("runCommand guard failed - bluetooth not running or peripheral not connected: peripheral %@", String(describing: peripheral))
            throw PeripheralManagerError.notReady
        }

        commandLock.lock()

        defer {
            commandLock.unlock()
        }

        guard commandConditions.isEmpty else {
            throw PeripheralManagerError.emptyValue
        }

        // Run
        command()

        guard !commandConditions.isEmpty else {
            // If the command didn't add any conditions, then finish immediately
            return
        }

        // Postlude
        let signaled = commandLock.wait(until: Date(timeIntervalSinceNow: timeout))

        defer {
            commandError = nil
            commandConditions = []
        }

        guard signaled else {
            self.log.info("runCommand lock timeout reached - not signalled")
            throw PeripheralManagerError.timeout(commandConditions)
        }

        if let error = commandError {
            throw PeripheralManagerError.cbPeripheralError(error)
        }
    }

    /// It's illegal to call this without first acquiring the commandLock
    ///
    /// - Parameter condition: The condition to add
    func addCondition(_ condition: CommandCondition) {
        dispatchPrecondition(condition: .onQueue(queue))
        commandConditions.append(condition)
    }

    func discoverServices(_ serviceUUIDs: [CBUUID], timeout: TimeInterval) throws {
        let servicesToDiscover = peripheral.servicesToDiscover(from: serviceUUIDs)

        guard servicesToDiscover.count > 0 else {
            return
        }

        try runCommand(timeout: timeout) {
            addCondition(.discoverServices)
            
            peripheral.discoverServices(serviceUUIDs)
        }
    }

    func discoverCharacteristics(_ characteristicUUIDs: [CBUUID], for service: CBService, timeout: TimeInterval) throws {
        let characteristicsToDiscover = peripheral.characteristicsToDiscover(from: characteristicUUIDs, for: service)

        guard characteristicsToDiscover.count > 0 else {
            return
        }

        try runCommand(timeout: timeout) {
            addCondition(.discoverCharacteristicsForService(serviceUUID: service.uuid))

            peripheral.discoverCharacteristics(characteristicsToDiscover, for: service)
        }
    }

    func reconnect(timeout: TimeInterval) throws {
        try runCommand(timeout: timeout) {
            addCondition(.connect)
            central?.cancelPeripheralConnection(peripheral)
        }
    }

    /// - Throws: PeripheralManagerError
    func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic, timeout: TimeInterval) throws {
        try runCommand(timeout: timeout) {
            addCondition(.notificationStateUpdate(characteristicUUID: characteristic.uuid, enabled: enabled))

            peripheral.setNotifyValue(enabled, for: characteristic)
        }
    }

    /// - Throws: PeripheralManagerError
    func readValue(for characteristic: CBCharacteristic, timeout: TimeInterval) throws -> Data? {
        try runCommand(timeout: timeout) {
            addCondition(.valueUpdate(characteristic: characteristic, matching: nil))

            peripheral.readValue(for: characteristic)
        }

        return characteristic.value
    }

    /// - Throws: PeripheralManagerError
    func writeValue(_ value: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType, timeout: TimeInterval) throws {
        try runCommand(timeout: timeout) {
            if case .withResponse = type {
                addCondition(.write(characteristic: characteristic))
            }

            peripheral.writeValue(value, for: characteristic, type: type)
        }
    }
}

// MARK: - Delegate methods executed on the central's queue
extension PeripheralManager: CBPeripheralDelegate {

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        log.default("didDiscoverServices")
        commandLock.lock()

        if let index = commandConditions.firstIndex(where: { (condition) -> Bool in
            if case .discoverServices = condition {
                return true
            } else {
                return false
            }
        }) {
            commandConditions.remove(at: index)
            commandError = error

            if commandConditions.isEmpty {
                commandLock.broadcast()
            }
        }

        commandLock.unlock()
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        commandLock.lock()

        if let index = commandConditions.firstIndex(where: { (condition) -> Bool in
            if case .discoverCharacteristicsForService(serviceUUID: service.uuid) = condition {
                return true
            } else {
                return false
            }
        }) {
            commandConditions.remove(at: index)
            commandError = error

            if commandConditions.isEmpty {
                commandLock.broadcast()
            }
        }

        commandLock.unlock()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        commandLock.lock()

        if let index = commandConditions.firstIndex(where: { (condition) -> Bool in
            if case .notificationStateUpdate(characteristicUUID: characteristic.uuid, enabled: characteristic.isNotifying) = condition {
                return true
            } else {
                return false
            }
        }) {
            commandConditions.remove(at: index)
            commandError = error

            if commandConditions.isEmpty {
                commandLock.broadcast()
            }
        }

        commandLock.unlock()
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        commandLock.lock()

        if let index = commandConditions.firstIndex(where: { condition in
            if case let .write(condChar) = condition, condChar === characteristic {
                return true
            } else {
                return false
            }
        }) {
            commandConditions.remove(at: index)
            commandError = error

            if commandConditions.isEmpty {
                commandLock.broadcast()
            }
        }

        commandLock.unlock()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        commandLock.lock()
        
        if let macro = configuration.valueUpdateMacros[characteristic.uuid] {
            macro(self)
        }

        if let index = commandConditions.firstIndex(where: { condition in
            if case let .valueUpdate(condChar, matching) = condition, condChar === characteristic {
                return matching?(characteristic.value) ?? true
            } else {
                return false
            }
        }) {
            commandConditions.remove(at: index)
            commandError = error

            if commandConditions.isEmpty {
                commandLock.broadcast()
            }
        }

        commandLock.unlock()

    }

    public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else {
            self.log.error("Error reading rssi: %{public}@", String(describing: RSSI))
            return
        }
        self.log.default("didReadRSSI: %{public}@", String(describing: RSSI))
    }

}


extension PeripheralManager {

    func clearCommsQueues() {
        queueLock.lock()
        if cmdQueue.count > 0 {
            self.log.default("Removing %{public}d leftover elements from command queue", cmdQueue.count)
            cmdQueue.removeAll()
        }
        queueLock.unlock()
    }

    func centralManager(_ central: CBCentralManager, didDisconnect peripheral: CBPeripheral, error: Error?) {
        self.idleStart = nil
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        self.log.debug("PeripheralManager - didConnect: %@", String(describing: peripheral))
        switch peripheral.state {
        case .connected:
            clearCommsQueues()
            self.log.debug("PeripheralManager - didConnect - running assertConfiguration")
            assertConfiguration()

            commandLock.lock()
            if let index = commandConditions.firstIndex(where: { (condition) -> Bool in
                if case .connect = condition {
                    return true
                } else {
                    return false
                }
            }) {
                commandConditions.remove(at: index)

                if commandConditions.isEmpty {
                    commandLock.broadcast()
                }
            }
            commandLock.unlock()

        default:
            break
        }
    }
}


// MARK: - Command session management
extension PeripheralManager {
    public func runSession(withName name: String, _ block: @escaping @Sendable () -> Void) {
        perform { _ in block() }
    }
}

// MARK: - Tandem Bluetooth Helpers
extension PeripheralManager {
    /// Sends raw data to the pump using the control characteristic.
    /// - Parameters:
    ///   - data: The packet data to transmit.
    ///   - timeout: Time to wait for the write to complete.
    /// - Throws: `PeripheralManagerError` when bluetooth is not ready or the write fails.
    func sendData(_ data: Data, characteristic: CBCharacteristic, timeout: TimeInterval) throws {
        dispatchPrecondition(condition: .onQueue(queue))
        try writeValue(data, for: characteristic, type: .withResponse, timeout: timeout)
    }

    /// Waits for a response packet to arrive on any of the pump characteristics.
    /// The received packet will be stored in `cmdQueue` by the value update macros.
    /// - Parameters:
    ///   - timeout: How long to wait for the notification.
    ///   - uuid: Optional characteristic UUID to match.
    /// - Throws: `PeripheralManagerError.timeout` if no packet is received.
    func waitForResponse(timeout: TimeInterval, matching uuid: CBUUID? = nil) throws {
        dispatchPrecondition(condition: .onQueue(queue))

        let waitUntil = Date(timeIntervalSinceNow: timeout)
        queueLock.lock()
        defer { queueLock.unlock() }

        while true {
            let hasData: Bool
            if let uuid {
                hasData = cmdQueue.contains(where: { $0.uuid == uuid })
            } else {
                hasData = !cmdQueue.isEmpty
            }

            if hasData {
                return
            }

            let signaled = queueLock.wait(until: waitUntil)
            if !signaled {
                throw PeripheralManagerError.timeout([])
            }
        }
    }

    /// Reads the next packet received from the pump for the specified characteristic.
    /// - Returns: Raw packet data if available.
    public func readMessagePacket(for uuid: CharacteristicUUID, timeout: TimeInterval = 15) throws -> Data? {
        dispatchPrecondition(condition: .onQueue(queue))

        try waitForResponse(timeout: timeout, matching: uuid.cbUUID)

        queueLock.lock()
        let index = cmdQueue.firstIndex(where: { $0.uuid == uuid.cbUUID })
        let cmd = index.flatMap { cmdQueue.remove(at: $0) }
        queueLock.unlock()
        if let value = cmd?.value {
            let hex = value.prefix(32).map { String(format: "%02X", $0) }.joined()
            logDebug("[PeripheralManager] read packet len=\(value.count) characteristic=\(uuid.prettyName) hex=\(hex)…")
        } else {
            logDebug("[PeripheralManager] read packet nil characteristic=\(uuid.prettyName)")
        }
        return cmd?.value
    }

    /// Convenience wrapper for sending a single message packet on a specific characteristic.
    func sendMessagePacket(_ data: Data, characteristic: CBCharacteristic) -> SendMessageResult {
        dispatchPrecondition(condition: .onQueue(queue))

        do {
            try sendData(data, characteristic: characteristic, timeout: 5)
            return .sentWithAcknowledgment
        } catch {
            return .unsentWithError(error)
        }
    }
}
