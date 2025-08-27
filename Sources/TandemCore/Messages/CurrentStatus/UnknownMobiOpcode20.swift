//
//  UnknownMobiOpcode20.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of UnknownMobiOpcode20Request and UnknownMobiOpcode20Response based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/UnknownMobiOpcode20Request.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/UnknownMobiOpcode20Response.java
//

import Foundation

/// Possibly related to Face ID authentication.
public class UnknownMobiOpcode20Request: Message {
    public static let props = MessageProps(
        opCode: 20,
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

/// Response to UnknownMobiOpcode20.
public class UnknownMobiOpcode20Response: Message {
    public static let props = MessageProps(
        opCode: 21,
        size: 3,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var status: Int
    public var unknown: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.status = Int(cargo[0])
        self.unknown = Bytes.readShort(cargo, 1)
    }

    public init(status: Int, unknown: Int) {
        self.cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(status),
            Bytes.firstTwoBytesLittleEndian(unknown)
        )
        self.status = status
        self.unknown = unknown
    }
}

