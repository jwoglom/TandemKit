//
//  LastBolusStatusV2.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of LastBolusStatusV2Request and LastBolusStatusV2Response based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/LastBolusStatusV2Request.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/LastBolusStatusV2Response.java
//

import Foundation

/// Request enhanced details about the last bolus (API 2.5+).
public class LastBolusStatusV2Request: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-92)),
        size: 0,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        minApi: .apiV2_5
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        self.cargo = Data()
    }
}

/// Response with enhanced last bolus information.
public class LastBolusStatusV2Response: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-91)),
        size: 24,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        minApi: .apiV2_5
    )

    public var cargo: Data
    public var status: Int
    public var bolusId: Int
    public var timestamp: UInt32
    public var deliveredVolume: UInt32
    public var bolusStatusId: Int
    public var bolusSourceId: Int
    public var bolusTypeBitmask: Int
    public var extendedBolusDuration: UInt32
    public var requestedVolume: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        self.status = Int(cargo[0])
        self.bolusId = Bytes.readShort(cargo, 1)
        self.timestamp = Bytes.readUint32(cargo, 5)
        self.deliveredVolume = Bytes.readUint32(cargo, 9)
        self.bolusStatusId = Int(cargo[13])
        self.bolusSourceId = Int(cargo[14])
        self.bolusTypeBitmask = Int(cargo[15])
        self.extendedBolusDuration = Bytes.readUint32(cargo, 16)
        self.requestedVolume = Bytes.readUint32(cargo, 20)
    }

    public init(status: Int, bolusId: Int, timestamp: UInt32, deliveredVolume: UInt32, bolusStatusId: Int, bolusSourceId: Int, bolusTypeBitmask: Int, extendedBolusDuration: UInt32, requestedVolume: UInt32) {
        self.cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(status),
            Bytes.firstTwoBytesLittleEndian(bolusId),
            Data([0,0]),
            Bytes.toUint32(timestamp),
            Bytes.toUint32(deliveredVolume),
            Bytes.firstByteLittleEndian(bolusStatusId),
            Bytes.firstByteLittleEndian(bolusSourceId),
            Bytes.firstByteLittleEndian(bolusTypeBitmask),
            Bytes.toUint32(extendedBolusDuration),
            Bytes.toUint32(requestedVolume)
        )
        self.status = status
        self.bolusId = bolusId
        self.timestamp = timestamp
        self.deliveredVolume = deliveredVolume
        self.bolusStatusId = bolusStatusId
        self.bolusSourceId = bolusSourceId
        self.bolusTypeBitmask = bolusTypeBitmask
        self.extendedBolusDuration = extendedBolusDuration
        self.requestedVolume = requestedVolume
    }

    public var bolusSource: BolusSource? { return BolusSource.fromId(bolusSourceId) }
    public var bolusTypes: Set<BolusType> { return BolusType.fromBitmask(bolusTypeBitmask) }
    public var timestampDate: Date { return Dates.fromJan12008EpochSecondsToDate(TimeInterval(timestamp)) }
}

