//
//  ChangeTimeDate.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of ChangeTimeDateRequest and ChangeTimeDateResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/ChangeTimeDateRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/ChangeTimeDateResponse.java
//

import Foundation

/// Request to change the pump's date/time.
public class ChangeTimeDateRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-42)),
        size: 4,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var tandemEpochTime: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        self.tandemEpochTime = Bytes.readUint32(cargo, 0)
    }

    public init(tandemEpochTime: UInt32) {
        self.cargo = Bytes.toUint32(tandemEpochTime)
        self.tandemEpochTime = tandemEpochTime
    }
}

/// Response containing status after changing date/time.
public class ChangeTimeDateResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-41)),
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

