//
//  UnknownMobiOpcodeNeg124.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of UnknownMobiOpcodeNeg124Request and UnknownMobiOpcodeNeg124Response based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/UnknownMobiOpcodeNeg124Request.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/UnknownMobiOpcodeNeg124Response.java
//

import Foundation

public class UnknownMobiOpcodeNeg124Request: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-124)),
        size: 0,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = Bytes.dropLastN(cargo, 20) // remove trailer if present
    }

    public init() {
        self.cargo = Data()
    }
}

public class UnknownMobiOpcodeNeg124Response: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-123)),
        size: 1,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data
    public var status: Int

    public required init(cargo: Data) {
        self.cargo = Bytes.dropLastN(cargo, 20)
        self.status = Int(self.cargo[0])
    }

    public init(status: Int) {
        self.cargo = Bytes.firstByteLittleEndian(status)
        self.status = status
    }
}

