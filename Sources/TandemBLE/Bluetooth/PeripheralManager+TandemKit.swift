//
//  PeripheralManager+TandemKit.swift
//  TandemKit
//
//  Created by James Woglom on 1/13/25.
//

import Foundation
import Dispatch
import TandemCore

public enum SendMessageResult {
    /// The packet was sent and the pump acknowledged receipt.
    case sentWithAcknowledgment

    /// The packet was sent but the pump responded with an error.
    case sentWithError(Error)

    /// The packet could not be sent because of a bluetooth error.
    case unsentWithError(Error)
}

extension PeripheralManager {
    public func performSync<T>(_ block: (_ manager: PeripheralManager) throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueSpecificKey) != nil {
            return try runConfigured(block)
        } else {
            return try queue.sync {
                try self.runConfigured(block)
            }
        }
    }

    
    public func enableNotifications() throws {
        dispatchPrecondition(condition: .onQueue(queue))
        print("[PeripheralManager] enableNotifications begin")

        for uuid in TandemNotificationOrder {
            guard let characteristic = peripheral.characteristic(for: uuid) else {
                if uuid == .SERVICE_CHANGED {
                    let services = peripheral.services?.map { $0.uuid.uuidString } ?? []
                    print("[PeripheralManager]   service-changed characteristic not exposed (services=\(services)); assuming availability per Tandem spec")
                    subscribedCharacteristicUUIDs.insert(uuid)
                    continue
                }
                let services = peripheral.services?.map { $0.uuid.uuidString } ?? []
                print("[PeripheralManager]   missing characteristic=\(uuid.prettyName) during subscription discoveredServices=\(services)")
                throw PeripheralManagerError.notReady
            }

            if subscribedCharacteristicUUIDs.contains(uuid) {
                print("[PeripheralManager]   notifications already enabled for \(uuid.prettyName); skipping")
                continue
            }

            print("[PeripheralManager]   enabling notifications for \(uuid.prettyName)")
            try setNotifyValue(true, for: characteristic, timeout: .seconds(2))
            subscribedCharacteristicUUIDs.insert(uuid)
            print("[PeripheralManager]   notifications enabled for \(uuid.prettyName)")
        }

        let required = Set(TandemNotificationOrder.filter { $0 != .SERVICE_CHANGED })
        let missing = required.subtracting(subscribedCharacteristicUUIDs)
        if !missing.isEmpty {
            print("[PeripheralManager]   notification subscription incomplete missing=\(missing.map { $0.prettyName })")
            throw PeripheralManagerError.notReady
        }

        if !subscribedCharacteristicUUIDs.contains(.SERVICE_CHANGED) {
            print("[PeripheralManager]   service-changed notifications assumed active by spec")
        }

        print("[PeripheralManager] enableNotifications complete")
    }
    
    
    public func sendMessagePackets(_ packets: [Packet], characteristic uuid: CharacteristicUUID) -> SendMessageResult {
        dispatchPrecondition(condition: .onQueue(queue))
        
        var didSend = false

        guard let characteristic = peripheral.characteristic(for: uuid) else {
            return .unsentWithError(PeripheralManagerError.notReady)
        }

        do {
            let pretty = uuid.prettyName
            for packet in packets {
                let hex = packet.build.map { String(format: "%02X", $0) }.joined()
                print("[PeripheralManager] write packet len=\(packet.build.count) characteristic=\(pretty) hex=\(hex)")
                try sendData(packet.build, characteristic: characteristic, timeout: 5)
            }
            didSend = true

            try waitForResponse(timeout: 15, matching: uuid.cbUUID)
        }
        catch {
            if didSend {
                print("[PeripheralManager] sendMessagePackets error after send: \(error)")
                return .sentWithError(error)
            } else {
                print("[PeripheralManager] sendMessagePackets error before send: \(error)")
                return .unsentWithError(error)
            }
        }
        return .sentWithAcknowledgment
    }
}
