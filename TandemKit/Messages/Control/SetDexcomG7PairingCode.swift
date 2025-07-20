//
//  SetDexcomG7PairingCode.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of SetDexcomG7PairingCodeRequest and SetDexcomG7PairingCodeResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/SetDexcomG7PairingCodeRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/SetDexcomG7PairingCodeResponse.java
//

import Foundation

/// Request to set a Dexcom G7 pairing code.
public class SetDexcomG7PairingCodeRequest: Message {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-4)),
        size: 8,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var pairingCode: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.pairingCode = Bytes.readShort(cargo, 0)
    }

    public init(pairingCode: Int) {
        self.cargo = Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(pairingCode),
            Data(repeating: 0, count: 6)
        )
        self.pairingCode = pairingCode
    }
}

/// Response after setting a Dexcom G7 pairing code.
public class SetDexcomG7PairingCodeResponse: Message, StatusMessage {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-3)),
        size: 2,
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
        self.cargo = Bytes.combine(
            Data([UInt8(status & 0xFF)]),
            Data([0])
        )
        self.status = status
    }
}

