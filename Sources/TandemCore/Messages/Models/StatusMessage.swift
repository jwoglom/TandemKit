//
//  StatusMessage.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift translation of StatusMessage
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/models/StatusMessage.java
//

import Foundation

/// Base protocol for response messages that include a status byte.
public protocol StatusMessage: Message {
    /// Status value where 0 indicates success.
    var status: Int { get }
}

public extension StatusMessage {
    /// Convenience accessor returning true if `status` equals zero.
    var isStatusOK: Bool { status == 0 }
}

