//
//  StopTempRate.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of StopTempRateRequest and StopTempRateResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/StopTempRateRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/StopTempRateResponse.java
//

import Foundation

/// Request to stop a running temp basal rate.
public class StopTempRateRequest: Message {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-90)),
        size: 0,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true,
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

/// Response after requesting a temp rate stop.
public class StopTempRateResponse: Message, StatusMessage {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-89)),
        size: 3,
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

