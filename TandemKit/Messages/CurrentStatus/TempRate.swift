//
//  TempRate.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of TempRateRequest and TempRateResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/TempRateRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/TempRateResponse.java
//

import Foundation

/// Request the current temporary basal rate information.
public class TempRateRequest: Message {
    public static var props = MessageProps(
        opCode: 42,
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

/// Response containing temporary basal rate details.
public class TempRateResponse: Message {
    public static var props = MessageProps(
        opCode: 43,
        size: 10,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var active: Bool
    public var percentage: Int
    public var startTimeRaw: UInt32
    public var duration: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        self.active = cargo[0] != 0
        self.percentage = Int(cargo[1])
        self.startTimeRaw = Bytes.readUint32(cargo, 2)
        self.duration = Bytes.readUint32(cargo, 6)
    }

    public init(active: Bool, percentage: Int, startTimeRaw: UInt32, duration: UInt32) {
        self.cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(active ? 1 : 0),
            Bytes.firstByteLittleEndian(percentage),
            Bytes.toUint32(startTimeRaw),
            Bytes.toUint32(duration)
        )
        self.active = active
        self.percentage = percentage
        self.startTimeRaw = startTimeRaw
        self.duration = duration
    }

    /// Convenience accessor converting `startTimeRaw` to `Date`.
    public var startTime: Date {
        return Dates.fromJan12008EpochSecondsToDate(TimeInterval(startTimeRaw))
    }
}

