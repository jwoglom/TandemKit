//
//  CurrentBolusStatus.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representation of CurrentBolusStatusRequest and CurrentBolusStatusResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/CurrentBolusStatusRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/CurrentBolusStatusResponse.java
//

import Foundation

/// Request information about any currently delivering bolus.
public class CurrentBolusStatusRequest: Message {
    public static var props = MessageProps(
        opCode: 44,
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

/// Response describing the currently active bolus, if any.
public class CurrentBolusStatusResponse: Message {
    public static var props = MessageProps(
        opCode: 45,
        size: 15,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var statusId: Int
    public var bolusId: Int
    public var timestamp: UInt32
    public var requestedVolume: UInt32
    public var bolusSourceId: Int
    public var bolusTypeBitmask: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.statusId = Int(cargo[0])
        self.bolusId = Bytes.readShort(cargo, 1)
        self.timestamp = Bytes.readUint32(cargo, 5)
        self.requestedVolume = Bytes.readUint32(cargo, 9)
        self.bolusSourceId = Int(cargo[13])
        self.bolusTypeBitmask = Int(cargo[14])
    }

    public init(statusId: Int, bolusId: Int, timestamp: UInt32, requestedVolume: UInt32, bolusSourceId: Int, bolusTypeBitmask: Int) {
        self.cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(statusId),
            Bytes.firstTwoBytesLittleEndian(bolusId),
            Data([0,0]),
            Bytes.toUint32(timestamp),
            Bytes.toUint32(requestedVolume),
            Bytes.firstByteLittleEndian(bolusSourceId),
            Bytes.firstByteLittleEndian(bolusTypeBitmask)
        )
        self.statusId = statusId
        self.bolusId = bolusId
        self.timestamp = timestamp
        self.requestedVolume = requestedVolume
        self.bolusSourceId = bolusSourceId
        self.bolusTypeBitmask = bolusTypeBitmask
    }

    public var status: CurrentBolusStatus? {
        return CurrentBolusStatus(rawValue: statusId)
    }

    public var bolusSource: BolusSource? {
        return BolusSource.fromId(bolusSourceId)
    }

    public var bolusTypes: Set<BolusType> {
        return BolusType.fromBitmask(bolusTypeBitmask)
    }

    public var timestampDate: Date {
        return Dates.fromJan12008EpochSecondsToDate(TimeInterval(timestamp))
    }

    /// Whether the data is valid (the bolus is still current).
    public var isValid: Bool {
        return !(status == .alreadyDeliveredOrInvalid && bolusId == 0 && timestamp == 0)
    }

    public enum CurrentBolusStatus: Int {
        case requesting = 2
        case delivering = 1
        case alreadyDeliveredOrInvalid = 0
    }
}
