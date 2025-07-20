//
//  SetMaxBolusLimit.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of SetMaxBolusLimitRequest and SetMaxBolusLimitResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/SetMaxBolusLimitRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/SetMaxBolusLimitResponse.java
//

import Foundation

/// Request to set the maximum bolus amount.
public class SetMaxBolusLimitRequest: Message {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-122)),
        size: 2,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var maxBolusMilliunits: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.maxBolusMilliunits = Bytes.readShort(cargo, 0)
    }

    public init(maxBolusMilliunits: Int) {
        self.cargo = Bytes.firstTwoBytesLittleEndian(maxBolusMilliunits)
        self.maxBolusMilliunits = maxBolusMilliunits
    }
}

/// Response after setting the max bolus limit.
public class SetMaxBolusLimitResponse: Message, StatusMessage {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-121)),
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

