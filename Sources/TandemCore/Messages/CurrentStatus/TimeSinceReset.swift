//
//  TimeSinceReset.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of TimeSinceResetRequest and TimeSinceResetResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/TimeSinceResetRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/TimeSinceResetResponse.java
//

import Foundation

/// Request information on the pump's internal time since reset.
public class TimeSinceResetRequest: Message {
    public static let props = MessageProps(
        opCode: 54,
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

/// Response with pump internal time data.
public class TimeSinceResetResponse: Message {
    public static let props = MessageProps(
        opCode: 55,
        size: 8,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var currentTime: UInt32
    public var pumpTimeSinceReset: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        self.currentTime = Bytes.readUint32(cargo, 0)
        self.pumpTimeSinceReset = Bytes.readUint32(cargo, 4)
    }

    public init(currentTime: UInt32, pumpTimeSinceReset: UInt32) {
        self.cargo = Bytes.combine(
            Bytes.toUint32(currentTime),
            Bytes.toUint32(pumpTimeSinceReset)
        )
        self.currentTime = currentTime
        self.pumpTimeSinceReset = pumpTimeSinceReset
    }

    /// Convenience accessor converting `currentTime` to `Date`.
    public var currentTimeDate: Date {
        return Dates.fromJan12008EpochSecondsToDate(TimeInterval(currentTime))
    }
}

