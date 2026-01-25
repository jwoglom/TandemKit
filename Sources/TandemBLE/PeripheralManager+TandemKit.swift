import CoreBluetooth
import Dispatch
import Foundation
import TandemCore

public enum SendMessageResult {
    /// The packet was sent and the pump acknowledged receipt.
    case sentWithAcknowledgment

    /// The packet was sent but the pump responded with an error.
    case sentWithError(Error)

    /// The packet could not be sent because of a bluetooth error.
    case unsentWithError(Error)
}

public protocol PeripheralManagerNotificationHandler: AnyObject {
    func peripheralManager(
        _ manager: PeripheralManager,
        didReceiveNotification value: Data,
        for characteristic: CBCharacteristic
    )
}

public extension PeripheralManager {
    func performSync<T>(_ block: (_ manager: PeripheralManager) throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueSpecificKey) != nil {
            return try runConfigured(block)
        } else {
            return try queue.sync {
                try self.runConfigured(block)
            }
        }
    }

    func enableNotifications() throws {
        dispatchPrecondition(condition: .onQueue(queue))
        logInfo("[PeripheralManager] enableNotifications begin")

        for uuid in TandemNotificationOrder {
            guard let characteristic = peripheral.characteristic(for: uuid) else {
                if uuid == .SERVICE_CHANGED {
                    let services = peripheral.services?.map(\.uuid.uuidString) ?? []
                    logWarning(
                        "[PeripheralManager]   service-changed characteristic not exposed (services=\(services)); assuming availability per Tandem spec"
                    )
                    subscribedCharacteristicUUIDs.insert(uuid)
                    continue
                }
                let services = peripheral.services?.map(\.uuid.uuidString) ?? []
                logWarning(
                    "[PeripheralManager]   missing characteristic=\(uuid.prettyName) during subscription discoveredServices=\(services)"
                )
                throw PeripheralManagerError.notReady
            }

            if subscribedCharacteristicUUIDs.contains(uuid) {
                logDebug("[PeripheralManager]   notifications already enabled for \(uuid.prettyName); skipping")
                continue
            }

            logDebug("[PeripheralManager]   enabling notifications for \(uuid.prettyName)")
            try setNotifyValue(true, for: characteristic, timeout: .seconds(2))
            subscribedCharacteristicUUIDs.insert(uuid)
            logDebug("[PeripheralManager]   notifications enabled for \(uuid.prettyName)")
        }

        let required = Set(TandemNotificationOrder.filter { $0 != .SERVICE_CHANGED })
        let missing = required.subtracting(subscribedCharacteristicUUIDs)
        if !missing.isEmpty {
            logWarning("[PeripheralManager]   notification subscription incomplete missing=\(missing.map(\.prettyName))")
            throw PeripheralManagerError.notReady
        }

        if !subscribedCharacteristicUUIDs.contains(.SERVICE_CHANGED) {
            logDebug("[PeripheralManager]   service-changed notifications assumed active by spec")
        }

        logInfo("[PeripheralManager] enableNotifications complete")
    }

    func sendMessagePackets(_ packets: [Packet], characteristic uuid: CharacteristicUUID) -> SendMessageResult {
        dispatchPrecondition(condition: .onQueue(queue))

        var didSend = false

        guard let characteristic = peripheral.characteristic(for: uuid) else {
            return .unsentWithError(PeripheralManagerError.notReady)
        }

        do {
            let pretty = uuid.prettyName
            for packet in packets {
                let hex = packet.build.map { String(format: "%02X", $0) }.joined()
                logDebug("[PeripheralManager] write packet len=\(packet.build.count) characteristic=\(pretty) hex=\(hex)")
                try sendData(packet.build, characteristic: characteristic, timeout: 5)
            }
            didSend = true

            try waitForResponse(timeout: 15, matching: uuid.cbUUID)
        } catch {
            if didSend {
                logError("[PeripheralManager] sendMessagePackets error after send: \(error)")
                return .sentWithError(error)
            } else {
                logError("[PeripheralManager] sendMessagePackets error before send: \(error)")
                return .unsentWithError(error)
            }
        }
        return .sentWithAcknowledgment
    }
}
