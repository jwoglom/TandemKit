//
//  PeripheralManager+TandemKit.swift
//  TandemKit
//
//  Created by James Woglom on 1/13/25.
//

import Foundation
import Dispatch

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
        guard let authChar = peripheral.getAuthorizationCharacteristic() else {
            throw PeripheralManagerError.notReady
        }
        guard let historyLogChar = peripheral.getHistoryLogCharacteristic() else {
            throw PeripheralManagerError.notReady
        }
        guard let controlChar = peripheral.getControlCharacteristic() else {
            throw PeripheralManagerError.notReady
        }
        guard let controlStreamChar = peripheral.getControlStreamCharacteristic() else {
            throw PeripheralManagerError.notReady
        }
        guard let currentStatusChar = peripheral.getCurrentStatusCharacteristic() else {
            throw PeripheralManagerError.notReady
        }
        guard let qualEventsChar = peripheral.getQualifyingEventsCharacteristic() else {
            throw PeripheralManagerError.notReady
        }
        try setNotifyValue(true, for: authChar, timeout: .seconds(2))
        try setNotifyValue(true, for: historyLogChar, timeout: .seconds(2))
        try setNotifyValue(true, for: controlChar, timeout: .seconds(2))
        try setNotifyValue(true, for: controlStreamChar, timeout: .seconds(2))
        try setNotifyValue(true, for: currentStatusChar, timeout: .seconds(2))
        try setNotifyValue(true, for: qualEventsChar, timeout: .seconds(2))
        print("[PeripheralManager] enableNotifications complete")
    }
    
    
    public func sendMessagePackets(_ packets: [Packet]) -> SendMessageResult {
        dispatchPrecondition(condition: .onQueue(queue))
        
        var didSend = false

        do {
            for packet in packets {
                let hex = packet.build.prefix(32).map { String(format: "%02X", $0) }.joined()
                print("[PeripheralManager] write packet len=\(packet.build.count) hex=\(hex)…")
                try sendData(packet.build, timeout: 5)
            }
            didSend = true

            try waitForResponse(timeout: 5)
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
