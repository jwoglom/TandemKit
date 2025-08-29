//
//  FillCannula.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of FillCannulaRequest and FillCannulaResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/FillCannulaRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/FillCannulaResponse.java
//

import Foundation

/// Request to fill the cannula with insulin. Pump must be suspended.
public class FillCannulaRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-104)),
        size: 2,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data
    public var primeSizeMilliUnits: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.primeSizeMilliUnits = Bytes.readShort(cargo, 0)
    }

    public init(primeSizeMilliUnits: Int) {
        self.cargo = Bytes.firstTwoBytesLittleEndian(primeSizeMilliUnits)
        self.primeSizeMilliUnits = primeSizeMilliUnits
    }
}

/// Response to FillCannulaRequest.
public class FillCannulaResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-103)),
        size: 1,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
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

