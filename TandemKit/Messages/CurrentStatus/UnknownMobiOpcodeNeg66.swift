//
//  UnknownMobiOpcodeNeg66.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of UnknownMobiOpcodeNeg66Request and UnknownMobiOpcodeNeg66Response based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/UnknownMobiOpcodeNeg66Request.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/UnknownMobiOpcodeNeg66Response.java
//

import Foundation

public class UnknownMobiOpcodeNeg66Request: Message {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-66)),
        size: 0,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        self.cargo = Data()
    }
}

public class UnknownMobiOpcodeNeg66Response: Message {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-65)),
        size: 20,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        self.cargo = Data()
    }
}

