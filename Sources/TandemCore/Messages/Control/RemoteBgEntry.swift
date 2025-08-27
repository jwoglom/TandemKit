//
//  RemoteBgEntry.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of RemoteBgEntryRequest and RemoteBgEntryResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/RemoteBgEntryRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/RemoteBgEntryResponse.java
//

import Foundation

/// Request to add a blood glucose entry on the pump during bolusing.
public class RemoteBgEntryRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-74)),
        size: 11,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .apiV2_5
    )

    public var cargo: Data
    public var bg: Int
    public var useForCgmCalibration: Bool
    public var isAutopopBg: Bool
    public var pumpTime: UInt32
    public var bolusId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.bg = Bytes.readShort(cargo, 0)
        self.useForCgmCalibration = cargo[2] == 1
        self.isAutopopBg = cargo[4] == 1
        self.pumpTime = Bytes.readUint32(cargo, 5)
        self.bolusId = Bytes.readShort(cargo, 9)
    }

    public init(bg: Int, useForCgmCalibration: Bool, isAutopopBg: Bool, pumpTime: UInt32, bolusId: Int) {
        self.cargo = Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(bg),
            Data([useForCgmCalibration ? 1 : 0]),
            Data([0]),
            Data([isAutopopBg ? 1 : 0]),
            Bytes.toUint32(pumpTime),
            Bytes.firstTwoBytesLittleEndian(bolusId)
        )
        self.bg = bg
        self.useForCgmCalibration = useForCgmCalibration
        self.isAutopopBg = isAutopopBg
        self.pumpTime = pumpTime
        self.bolusId = bolusId
    }
}

/// Response after adding a BG entry.
public class RemoteBgEntryResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-73)),
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

