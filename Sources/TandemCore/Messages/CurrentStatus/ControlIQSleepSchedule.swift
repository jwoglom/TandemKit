//
//  ControlIQSleepSchedule.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of ControlIQSleepScheduleRequest and ControlIQSleepScheduleResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/ControlIQSleepScheduleRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/ControlIQSleepScheduleResponse.java
//

import Foundation

/// Request the Control-IQ sleep schedule settings.
public class ControlIQSleepScheduleRequest: Message {
    public static let props = MessageProps(
        opCode: 106,
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

/// Response containing up to four sleep schedule segments.
public class ControlIQSleepScheduleResponse: Message {
    public static let props = MessageProps(
        opCode: 107,
        size: 24,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var schedule0: SleepSchedule
    public var schedule1: SleepSchedule
    public var schedule2: SleepSchedule
    public var schedule3: SleepSchedule

    public required init(cargo: Data) {
        self.cargo = cargo
        self.schedule0 = SleepSchedule(data: cargo, index: 0)
        self.schedule1 = SleepSchedule(data: cargo, index: 6)
        self.schedule2 = SleepSchedule(data: cargo, index: 12)
        self.schedule3 = SleepSchedule(data: cargo, index: 18)
    }

    public init(schedule0: SleepSchedule, schedule1: SleepSchedule, schedule2: SleepSchedule, schedule3: SleepSchedule) {
        self.cargo = Bytes.combine(
            schedule0.build(),
            schedule1.build(),
            schedule2.build(),
            schedule3.build()
        )
        self.schedule0 = schedule0
        self.schedule1 = schedule1
        self.schedule2 = schedule2
        self.schedule3 = schedule3
    }

    /// Represents a single sleep schedule block.
    public struct SleepSchedule {
        public var enabled: Int
        public var activeDays: Int
        public var startTime: Int
        public var endTime: Int

        public init(data: Data, index: Int) {
            self.enabled = Int(data[index])
            self.activeDays = Int(data[index + 1])
            self.startTime = Bytes.readShort(data, index + 2)
            self.endTime = Bytes.readShort(data, index + 4)
        }

        public init(enabled: Int, activeDays: Int, startTime: Int, endTime: Int) {
            self.enabled = enabled
            self.activeDays = activeDays
            self.startTime = startTime
            self.endTime = endTime
        }

        public func build() -> Data {
            return Bytes.combine(
                Bytes.firstByteLittleEndian(enabled),
                Bytes.firstByteLittleEndian(activeDays),
                Bytes.firstTwoBytesLittleEndian(startTime),
                Bytes.firstTwoBytesLittleEndian(endTime)
            )
        }
    }
}

