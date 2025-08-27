//
//  PlaySound.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of PlaySoundRequest and PlaySoundResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/PlaySoundRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/PlaySoundResponse.java
//

import Foundation

/// Request to play a notification sound on the pump.
public class PlaySoundRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-12)),
        size: 0,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        self.cargo = Data()
    }
}

/// Response after requesting a sound to be played.
public class PlaySoundResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-11)),
        size: 1,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var status: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.status = Int(cargo[0])
    }

    public init(status: Int) {
        self.cargo = Data([UInt8(status & 0xFF)])
        self.status = status
    }
}

