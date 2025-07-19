//
//  UnknownMobiOpcode30.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of UnknownMobiOpcode30Request and UnknownMobiOpcode30Response based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/UnknownMobiOpcode30Request.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/UnknownMobiOpcode30Response.java
//

import Foundation

public class UnknownMobiOpcode30Request: Message {
    public static var props = MessageProps(
        opCode: 30,
        size: 0,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        self.cargo = Data()
    }
}

public class UnknownMobiOpcode30Response: Message {
    public static var props = MessageProps(
        opCode: 31,
        size: 16,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var unknown1: UInt32
    public var unknown2: UInt32
    public var unknown3: UInt32
    public var unknown4: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        self.unknown1 = Bytes.readUint32(cargo, 0)
        self.unknown2 = Bytes.readUint32(cargo, 4)
        self.unknown3 = Bytes.readUint32(cargo, 8)
        self.unknown4 = Bytes.readUint32(cargo, 12)
    }

    public init(unknown1: UInt32, unknown2: UInt32, unknown3: UInt32, unknown4: UInt32) {
        self.cargo = Bytes.combine(
            Bytes.toUint32(unknown1),
            Bytes.toUint32(unknown2),
            Bytes.toUint32(unknown3),
            Bytes.toUint32(unknown4)
        )
        self.unknown1 = unknown1
        self.unknown2 = unknown2
        self.unknown3 = unknown3
        self.unknown4 = unknown4
    }
}

