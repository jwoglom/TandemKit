//
//  NonControlIQIOB.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of NonControlIQIOBRequest and NonControlIQIOBResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/NonControlIQIOBRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/NonControlIQIOBResponse.java
//

import Foundation

/// Request insulin on board information when Control-IQ is not supported.
public class NonControlIQIOBRequest: Message {
    public static let props = MessageProps(
        opCode: 38,
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

/// Response providing IOB information when Control-IQ is not supported.
public class NonControlIQIOBResponse: Message {
    public static let props = MessageProps(
        opCode: 39,
        size: 12,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var iob: UInt32
    public var timeRemaining: UInt32
    public var totalIOB: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        self.iob = Bytes.readUint32(cargo, 0)
        self.timeRemaining = Bytes.readUint32(cargo, 4)
        self.totalIOB = Bytes.readUint32(cargo, 8)
    }

    public init(iob: UInt32, timeRemaining: UInt32, totalIOB: UInt32) {
        self.cargo = Bytes.combine(
            Bytes.toUint32(iob),
            Bytes.toUint32(timeRemaining),
            Bytes.toUint32(totalIOB)
        )
        self.iob = iob
        self.timeRemaining = timeRemaining
        self.totalIOB = totalIOB
    }
}

