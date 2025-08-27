//
//  RemoteCarbEntry.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of RemoteCarbEntryRequest and RemoteCarbEntryResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/RemoteCarbEntryRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/RemoteCarbEntryResponse.java
//

import Foundation

/// Request to attach carbohydrate info to an in-progress bolus.
public class RemoteCarbEntryRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-14)),
        size: 9,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .apiV2_5
    )

    public var cargo: Data
    public var carbs: Int
    public var unknown: Int
    public var pumpTime: UInt32
    public var bolusId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.carbs = Bytes.readShort(cargo, 0)
        self.unknown = Int(cargo[2])
        self.pumpTime = Bytes.readUint32(cargo, 3)
        self.bolusId = Bytes.readShort(cargo, 7)
    }

    public init(carbs: Int, pumpTime: UInt32, bolusId: Int, unknown: Int = 1) {
        self.cargo = Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(carbs),
            Data([UInt8(unknown & 0xFF)]),
            Bytes.toUint32(pumpTime),
            Bytes.firstTwoBytesLittleEndian(bolusId)
        )
        self.carbs = carbs
        self.unknown = unknown
        self.pumpTime = pumpTime
        self.bolusId = bolusId
    }
}

/// Response after attaching carb info.
public class RemoteCarbEntryResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-13)),
        size: 1,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .apiV2_5
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

