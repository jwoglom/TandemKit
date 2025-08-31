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
#if os(macOS)
import os
#endif

class PeripheralManager: NSObject, @unchecked Sendable {

    private let log = OSLog(category: "PeripheralManager")

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

    var needsReconnection: Bool {
        guard let start = idleStart else { return false }

        return Date().timeIntervalSince(start) > .minutes(2.9)
    }


    /// The dispatch queue used to serialize operations on the peripheral
    let queue = DispatchQueue(label: "com.jwoglom.TandemKit.PeripheralManager.queue", qos: .unspecified)

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

        assertConfiguration()
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
}


// MARK: - Operation sequence management
extension PeripheralManager {


    func configureAndRun(_ block: @escaping @Sendable (_ manager: PeripheralManager) -> Void) -> @Sendable () -> Void {
        return {
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

            block(self)
        }
    }

    func perform(_ block: @escaping @Sendable (_ manager: PeripheralManager) -> Void) {
        queue.async(execute: configureAndRun(block))
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

        for (serviceUUID, characteristicUUIDs) in configuration.notifyingCharacteristics {
            guard let service = peripheral.services?.itemWithUUID(serviceUUID) else {
                throw PeripheralManagerError.unknownCharacteristic(serviceUUID)
            }

            for characteristicUUID in characteristicUUIDs {
                guard let characteristic = service.characteristics?.itemWithUUID(characteristicUUID) else {
                    throw PeripheralManagerError.unknownCharacteristic(characteristicUUID)
                }

                guard !characteristic.isNotifying else {
                    continue
                }

                try setNotifyValue(true, for: characteristic, timeout: discoveryTimeout)
            }
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

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
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

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
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

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
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

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
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

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
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

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
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
    func sendData(_ data: Data, timeout: TimeInterval) throws {
        dispatchPrecondition(condition: .onQueue(queue))

        guard let characteristic = peripheral.getControlCharacteristic() else {
            throw PeripheralManagerError.notReady
        }

        try writeValue(data, for: characteristic, type: .withResponse, timeout: timeout)
    }

    /// Waits for a response packet to arrive on any of the pump characteristics.
    /// The received packet will be stored in `cmdQueue` by the value update macros.
    /// - Parameter timeout: How long to wait for the notification.
    /// - Throws: `PeripheralManagerError.timeout` if no packet is received.
    func waitForResponse(timeout: TimeInterval) throws {
        dispatchPrecondition(condition: .onQueue(queue))

        let waitUntil = Date(timeIntervalSinceNow: timeout)
        queueLock.lock()
        while cmdQueue.isEmpty && queueLock.wait(until: waitUntil) {}
        let hasData = !cmdQueue.isEmpty
        queueLock.unlock()

        if !hasData {
            throw PeripheralManagerError.timeout([])
        }
    }

    /// Reads the next packet received from the pump.
    /// - Returns: Raw packet data if available.
    func readMessagePacket() throws -> Data? {
        dispatchPrecondition(condition: .onQueue(queue))

        try waitForResponse(timeout: 5)

        queueLock.lock()
        let cmd = cmdQueue.isEmpty ? nil : cmdQueue.removeFirst()
        queueLock.unlock()
        return cmd?.value
    }

    /// Convenience wrapper for sending a single message packet.
    func sendMessagePacket(_ data: Data) -> SendMessageResult {
        dispatchPrecondition(condition: .onQueue(queue))

        do {
            try sendData(data, timeout: 5)
            return .sentWithAcknowledgment
        } catch {
            return .unsentWithError(error)
        }
    }
}
