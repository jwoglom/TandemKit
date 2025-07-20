//
//  EnterChangeCartridgeMode.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of EnterChangeCartridgeModeRequest and EnterChangeCartridgeModeResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/EnterChangeCartridgeModeRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/EnterChangeCartridgeModeResponse.java
//

import Foundation

/// Request to enter change cartridge mode (pump must be suspended).
public class EnterChangeCartridgeModeRequest: Message {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-112)),
        size: 0,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        self.cargo = Data()
    }
}

/// Response after entering change cartridge mode.
public class EnterChangeCartridgeModeResponse: Message, StatusMessage {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-111)),
        size: 1,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true
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

