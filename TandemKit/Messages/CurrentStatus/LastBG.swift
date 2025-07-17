//
//  LastBG.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representation of LastBGRequest and LastBGResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/LastBGRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/LastBGResponse.java
//

import Foundation

/// Request the last BG entered via the Bolus Calculator.
public class LastBGRequest: Message {
    public static var props = MessageProps(
        opCode: 50,
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

/// Response containing the last manually entered BG.
public class LastBGResponse: Message {
    public static var props = MessageProps(
        opCode: 51,
        size: 7,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var bgTimestamp: UInt32
    public var bgValue: Int
    public var bgSourceId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.bgTimestamp = Bytes.readUint32(cargo, 0)
        self.bgValue = Bytes.readShort(cargo, 4)
        self.bgSourceId = Int(cargo[6])
    }

    public init(bgTimestamp: UInt32, bgValue: Int, bgSourceId: Int) {
        self.cargo = Bytes.combine(
            Bytes.toUint32(bgTimestamp),
            Bytes.firstTwoBytesLittleEndian(bgValue),
            Bytes.firstByteLittleEndian(bgSourceId)
        )
        self.bgTimestamp = bgTimestamp
        self.bgValue = bgValue
        self.bgSourceId = bgSourceId
    }

    public var bgSource: BgSource? {
        return BgSource(rawValue: bgSourceId)
    }

    public var bgTimestampDate: Date {
        return Dates.fromJan12008EpochSecondsToDate(TimeInterval(bgTimestamp))
    }

    public enum BgSource: Int {
        case manual = 0
        case cgm = 1
    }
}
