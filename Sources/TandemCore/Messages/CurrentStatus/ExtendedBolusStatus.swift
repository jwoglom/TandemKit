//
//  ExtendedBolusStatus.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of ExtendedBolusStatusRequest and ExtendedBolusStatusResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/ExtendedBolusStatusRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/ExtendedBolusStatusResponse.java
//

import Foundation

/// Request information on the current extended bolus.
public class ExtendedBolusStatusRequest: Message {
    public static let props = MessageProps(
        opCode: 46,
        size: 0,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        self.cargo = Data()
    }
}

/// Response describing details of the current extended bolus.
public class ExtendedBolusStatusResponse: Message {
    public static let props = MessageProps(
        opCode: 47,
        size: 18,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var bolusStatus: Int
    public var bolusId: Int
    public var timestamp: UInt32
    public var requestedVolume: UInt32
    public var duration: UInt32
    public var bolusSource: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.bolusStatus = Int(cargo[0])
        self.bolusId = Bytes.readShort(cargo, 1)
        self.timestamp = Bytes.readUint32(cargo, 5)
        self.requestedVolume = Bytes.readUint32(cargo, 9)
        self.duration = Bytes.readUint32(cargo, 13)
        self.bolusSource = Int(cargo[17])
    }

    public init(bolusStatus: Int, bolusId: Int, timestamp: UInt32, requestedVolume: UInt32, duration: UInt32, bolusSource: Int) {
        self.cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(bolusStatus),
            Bytes.firstTwoBytesLittleEndian(bolusId),
            Bytes.toUint32(timestamp),
            Bytes.toUint32(requestedVolume),
            Bytes.toUint32(duration),
            Bytes.firstByteLittleEndian(bolusSource),
            Data([0, 0])
        )
        self.bolusStatus = bolusStatus
        self.bolusId = bolusId
        self.timestamp = timestamp
        self.requestedVolume = requestedVolume
        self.duration = duration
        self.bolusSource = bolusSource
    }
}

