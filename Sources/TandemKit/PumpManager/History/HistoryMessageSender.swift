//
//  HistoryMessageSender.swift
//  TandemKit
//
//  Decouples the history fetch pipeline from the concrete BLE transport. On the dev
//  line, TandemBluetoothManager.write(message:expecting:) provides the synchronous
//  request/response used by HistoryFetchSession. Tests inject a mock conforming type.
//

import Foundation

/// Synchronously sends a pump request and returns the matching response, or nil on
/// timeout / no response. Mirrors the shape of `TandemBluetoothManager.write`.
protocol HistoryMessageSender {
    func sendMessage(_ message: Message, expecting: Message.Type) -> Message?
}

extension TandemBluetoothManager: HistoryMessageSender {
    func sendMessage(_ message: Message, expecting: Message.Type) -> Message? {
        write(message: message, expecting: expecting)
    }
}
