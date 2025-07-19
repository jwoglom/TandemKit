//
//  OtherNotification2Status.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of OtherNotification2StatusRequest and OtherNotification2StatusResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/OtherNotification2StatusRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/OtherNotification2StatusResponse.java
//

import Foundation

/// Request additional notification status codes.
public class OtherNotification2StatusRequest: Message {
    public static var props = MessageProps(
        opCode: 118,
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

/// Response containing two additional notification codes.
public class OtherNotification2StatusResponse: Message {
    public static var props = MessageProps(
        opCode: 119,
        size: 8,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var codeA: UInt32
    public var codeB: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        self.codeA = Bytes.readUint32(cargo, 0)
        self.codeB = Bytes.readUint32(cargo, 4)
    }

    public init(codeA: UInt32, codeB: UInt32) {
        self.cargo = Bytes.combine(
            Bytes.toUint32(codeA),
            Bytes.toUint32(codeB)
        )
        self.codeA = codeA
        self.codeB = codeB
    }
}

