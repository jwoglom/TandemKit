//
//  SetTempRate.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of SetTempRateRequest and SetTempRateResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/SetTempRateRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/SetTempRateResponse.java
//

import Foundation

/// Request to set a temporary basal rate.
public class SetTempRateRequest: Message {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-92)),
        size: 6,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data
    public var minutes: Int
    public var percent: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        let ms = Bytes.readUint32(cargo, 0)
        self.minutes = Int(ms) / 1000 / 60
        self.percent = Bytes.readShort(cargo, 4)
    }

    public init(minutes: Int, percent: Int) {
        self.cargo = Bytes.combine(
            Bytes.toUint32(UInt32(minutes * 60 * 1000)),
            Bytes.firstTwoBytesLittleEndian(percent)
        )
        self.minutes = minutes
        self.percent = percent
    }
}

/// Response confirming a temp rate was set.
public class SetTempRateResponse: Message, StatusMessage {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-91)),
        size: 4,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data
    public var status: Int
    public var tempRateId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.status = Int(cargo[0])
        self.tempRateId = Bytes.readShort(cargo, 1)
    }

    public init(status: Int, tempRateId: Int) {
        self.cargo = Bytes.combine(
            Data([UInt8(status & 0xFF)]),
            Bytes.firstTwoBytesLittleEndian(tempRateId)
        )
        self.status = status
        self.tempRateId = tempRateId
    }
}

