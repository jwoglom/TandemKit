//
//  ExitChangeCartridgeMode.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of ExitChangeCartridgeModeRequest and ExitChangeCartridgeModeResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/ExitChangeCartridgeModeRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/ExitChangeCartridgeModeResponse.java
//

import Foundation

/// Request to exit change cartridge mode after new cartridge inserted.
public class ExitChangeCartridgeModeRequest: Message {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-110)),
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

/// Response confirming exit from change cartridge mode.
public class ExitChangeCartridgeModeResponse: Message, StatusMessage {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-109)),
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

