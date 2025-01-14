//
//  PeripheralManager+TandemKit.swift
//  TandemKit
//
//  Created by James Woglom on 1/13/25.
//


enum SendMessageResult {
    case sentWithAcknowledgment
    case sentWithError
}

extension PeripheralManager {
    
    func enableNotifications() throws {
        dispatchPrecondition(condition: .onQueue(queue))
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
    }
    
    
    func sendMessagePackets(_ packets: [Packet]) -> SendMessageResult {
        dispatchPrecondition(condition: .onQueue(queue))
        
        var didSend = false

        do {
            for (index, packet) in packets.enumerated() {
                // Consider starting the last packet send as the point at which the message may be received by the pod.
                // A failure after data is actually sent, but before the sendData() returns can still be received.
                if index == packets.count - 1 {
                    didSend = true
                }
                try sendData(packet.toData(), timeout: 5)
                try self.peekForNack()
            }

            try waitForCommand(PodCommand.SUCCESS, timeout: 5)
        }
        catch {
            if didSend {
                return .sentWithError(error)
            } else {
                return .unsentWithError(error)
            }
        }
        return .sentWithAcknowledgment
    }
}
