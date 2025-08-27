//
//  InitiateBolus.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of InitiateBolusRequest and InitiateBolusResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/control/InitiateBolusRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/control/InitiateBolusResponse.java
//

import Foundation

/// Request to start a bolus after receiving permission.
public class InitiateBolusRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-98)),
        size: 37,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true
    )

    public var cargo: Data
    public var totalVolume: UInt32
    public var bolusID: Int
    public var bolusTypeBitmask: Int
    public var foodVolume: UInt32
    public var correctionVolume: UInt32
    public var bolusCarbs: Int
    public var bolusBG: Int
    public var bolusIOB: UInt32
    public var extendedVolume: UInt32
    public var extendedSeconds: UInt32
    public var extended3: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        self.totalVolume = Bytes.readUint32(cargo, 0)
        self.bolusID = Bytes.readShort(cargo, 4)
        self.bolusTypeBitmask = Int(cargo[8])
        self.foodVolume = Bytes.readUint32(cargo, 9)
        self.correctionVolume = Bytes.readUint32(cargo, 13)
        self.bolusCarbs = Bytes.readShort(cargo, 17)
        self.bolusBG = Bytes.readShort(cargo, 19)
        self.bolusIOB = Bytes.readUint32(cargo, 21)
        self.extendedVolume = Bytes.readUint32(cargo, 25)
        self.extendedSeconds = Bytes.readUint32(cargo, 29)
        self.extended3 = Bytes.readUint32(cargo, 33)
    }

    public init(totalVolume: UInt32, bolusID: Int, bolusTypeBitmask: Int, foodVolume: UInt32, correctionVolume: UInt32, bolusCarbs: Int, bolusBG: Int, bolusIOB: UInt32, extendedVolume: UInt32 = 0, extendedSeconds: UInt32 = 0, extended3: UInt32 = 0) {
        self.cargo = InitiateBolusRequest.buildCargo(totalVolume: totalVolume, bolusID: bolusID, bolusTypeBitmask: bolusTypeBitmask, foodVolume: foodVolume, correctionVolume: correctionVolume, bolusCarbs: bolusCarbs, bolusBG: bolusBG, bolusIOB: bolusIOB, extendedVolume: extendedVolume, extendedSeconds: extendedSeconds, extended3: extended3)
        self.totalVolume = totalVolume
        self.bolusID = bolusID
        self.bolusTypeBitmask = bolusTypeBitmask
        self.foodVolume = foodVolume
        self.correctionVolume = correctionVolume
        self.bolusCarbs = bolusCarbs
        self.bolusBG = bolusBG
        self.bolusIOB = bolusIOB
        self.extendedVolume = extendedVolume
        self.extendedSeconds = extendedSeconds
        self.extended3 = extended3
    }

    public static func buildCargo(totalVolume: UInt32, bolusID: Int, bolusTypeBitmask: Int, foodVolume: UInt32, correctionVolume: UInt32, bolusCarbs: Int, bolusBG: Int, bolusIOB: UInt32, extendedVolume: UInt32, extendedSeconds: UInt32, extended3: UInt32) -> Data {
        return Bytes.combine(
            Bytes.toUint32(totalVolume),
            Bytes.firstTwoBytesLittleEndian(bolusID),
            Data([0, 0]),
            Data([UInt8(bolusTypeBitmask & 0xFF)]),
            Bytes.toUint32(foodVolume),
            Bytes.toUint32(correctionVolume),
            Bytes.firstTwoBytesLittleEndian(bolusCarbs),
            Bytes.firstTwoBytesLittleEndian(bolusBG),
            Bytes.toUint32(bolusIOB),
            Bytes.toUint32(extendedVolume),
            Bytes.toUint32(extendedSeconds),
            Bytes.toUint32(extended3)
        )
    }

    public var bolusTypes: Set<BolusType> { BolusType.fromBitmask(bolusTypeBitmask) }
}

/// Response after initiating a bolus.
public class InitiateBolusResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-97)),
        size: 6,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true
    )

    public var cargo: Data
    public var status: Int
    public var bolusId: Int
    public var statusTypeId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.status = Int(cargo[0])
        self.bolusId = Bytes.readShort(cargo, 1)
        self.statusTypeId = Int(cargo[5])
    }

    public init(status: Int, bolusId: Int, statusTypeId: Int) {
        self.cargo = InitiateBolusResponse.buildCargo(status: status, bolusId: bolusId, statusTypeId: statusTypeId)
        self.status = status
        self.bolusId = bolusId
        self.statusTypeId = statusTypeId
    }

    public static func buildCargo(status: Int, bolusId: Int, statusTypeId: Int) -> Data {
        return Bytes.combine(
            Data([UInt8(status & 0xFF)]),
            Bytes.firstTwoBytesLittleEndian(bolusId),
            Data([0,0]),
            Data([UInt8(statusTypeId & 0xFF)])
        )
    }

    public enum BolusResponseStatus: Int {
        case success = 0
        case revokedPriority = 2
    }

    public var statusType: BolusResponseStatus? { BolusResponseStatus(rawValue: statusTypeId) }
    public var wasBolusInitiated: Bool { status == 0 && statusType == .success }
}

