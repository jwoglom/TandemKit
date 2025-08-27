//
//  Reminders.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of RemindersRequest and RemindersResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/RemindersRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/RemindersResponse.java
//

import Foundation

/// Request configured reminders from the pump.
public class RemindersRequest: Message {
    public static let props = MessageProps(
        opCode: 88,
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

/// Response with reminder configuration details.
public class RemindersResponse: Message {
    public static let props = MessageProps(
        opCode: 89,
        size: 105,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var lowBGReminder: Reminder
    public var highBGReminder: Reminder
    public var siteChangeReminder: Reminder
    public var missedBolusReminder0: Reminder
    public var missedBolusReminder1: Reminder
    public var missedBolusReminder2: Reminder
    public var missedBolusReminder3: Reminder
    public var afterBolusReminder: Reminder
    public var additionalBolusReminder: Reminder
    public var lowBGThreshold: Int
    public var highBGThreshold: Int
    public var siteChangeDays: Int
    public var status: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.lowBGReminder = Reminder(data: cargo, index: 0)
        self.highBGReminder = Reminder(data: cargo, index: 11)
        self.siteChangeReminder = Reminder(data: cargo, index: 22)
        self.missedBolusReminder0 = Reminder(data: cargo, index: 33)
        self.missedBolusReminder1 = Reminder(data: cargo, index: 44)
        self.missedBolusReminder2 = Reminder(data: cargo, index: 55)
        self.missedBolusReminder3 = Reminder(data: cargo, index: 66)
        self.afterBolusReminder = Reminder(data: cargo, index: 77)
        self.additionalBolusReminder = Reminder(data: cargo, index: 88)
        self.lowBGThreshold = Bytes.readShort(cargo, 99)
        self.highBGThreshold = Bytes.readShort(cargo, 101)
        self.siteChangeDays = Int(cargo[103])
        self.status = Int(cargo[104])
    }

    public init(lowBGReminder: Reminder, highBGReminder: Reminder, siteChangeReminder: Reminder, missedBolusReminder0: Reminder, missedBolusReminder1: Reminder, missedBolusReminder2: Reminder, missedBolusReminder3: Reminder, afterBolusReminder: Reminder, additionalBolusReminder: Reminder, lowBGThreshold: Int, highBGThreshold: Int, siteChangeDays: Int, status: Int) {
        self.cargo = Bytes.combine(
            lowBGReminder.buildCargo(),
            highBGReminder.buildCargo(),
            siteChangeReminder.buildCargo(),
            missedBolusReminder0.buildCargo(),
            missedBolusReminder1.buildCargo(),
            missedBolusReminder2.buildCargo(),
            missedBolusReminder3.buildCargo(),
            afterBolusReminder.buildCargo(),
            additionalBolusReminder.buildCargo(),
            Bytes.firstTwoBytesLittleEndian(lowBGThreshold),
            Bytes.firstTwoBytesLittleEndian(highBGThreshold),
            Bytes.firstByteLittleEndian(siteChangeDays),
            Bytes.firstByteLittleEndian(status)
        )
        self.lowBGReminder = lowBGReminder
        self.highBGReminder = highBGReminder
        self.siteChangeReminder = siteChangeReminder
        self.missedBolusReminder0 = missedBolusReminder0
        self.missedBolusReminder1 = missedBolusReminder1
        self.missedBolusReminder2 = missedBolusReminder2
        self.missedBolusReminder3 = missedBolusReminder3
        self.afterBolusReminder = afterBolusReminder
        self.additionalBolusReminder = additionalBolusReminder
        self.lowBGThreshold = lowBGThreshold
        self.highBGThreshold = highBGThreshold
        self.siteChangeDays = siteChangeDays
        self.status = status
    }

    /// Reminder record containing timing and enablement information.
    public struct Reminder {
        public var frequency: UInt32
        public var startTime: UInt16
        public var endTime: UInt16
        public var activeDays: UInt8
        public var enabled: UInt8
        public var validityStatus: UInt8

        public init(frequency: UInt32, startTime: UInt16, endTime: UInt16, activeDays: UInt8, enabled: UInt8, validityStatus: UInt8) {
            self.frequency = frequency
            self.startTime = startTime
            self.endTime = endTime
            self.activeDays = activeDays
            self.enabled = enabled
            self.validityStatus = validityStatus
        }

        public init(data: Data, index: Int) {
            self.frequency = Bytes.readUint32(data, index)
            self.startTime = UInt16(Bytes.readShort(data, index + 4))
            self.endTime = UInt16(Bytes.readShort(data, index + 6))
            self.activeDays = data[index + 8]
            self.enabled = data[index + 9]
            self.validityStatus = data[index + 10]
        }

        public func buildCargo() -> Data {
            return Bytes.combine(
                Bytes.toUint32(frequency),
                Bytes.firstTwoBytesLittleEndian(Int(startTime)),
                Bytes.firstTwoBytesLittleEndian(Int(endTime)),
                Bytes.firstByteLittleEndian(Int(activeDays)),
                Bytes.firstByteLittleEndian(Int(enabled)),
                Bytes.firstByteLittleEndian(Int(validityStatus))
            )
        }

        /// Days of the week this reminder is active.
        public var activeDaysSet: Set<MultiDay> {
            return MultiDay.fromBitmask(Int(activeDays))
        }
    }
}

/// Representation of a HH:MM timestamp in minutes.
public struct MinsTime: Equatable, CustomStringConvertible {
    public var hour: Int
    public var min: Int

    public init(_ totalMins: Int) {
        self.hour = totalMins / 60
        self.min = totalMins % 60
    }

    public init(hour: Int, min: Int) {
        self.hour = hour
        self.min = min
    }

    public var encode: Int { return hour * 60 + min }
    public var description: String { String(format: "%02d:%02d", hour, min) }
}

/// Days of the week bitmask helper.
public enum MultiDay: Int, CaseIterable, Sendable {
    case monday = 1
    case tuesday = 2
    case wednesday = 4
    case thursday = 8
    case friday = 16
    case saturday = 32
    case sunday = 64

    public static func fromBitmask(_ bitmask: Int) -> Set<MultiDay> {
        var set = Set<MultiDay>()
        for day in MultiDay.allCases {
            if (bitmask & day.rawValue) != 0 { set.insert(day) }
        }
        return set
    }

    public static func toBitmask(_ days: [MultiDay]) -> Int {
        var mask = 0
        for day in days { mask |= day.rawValue }
        return mask
    }

    public static let allDays: Set<MultiDay> = Set(MultiDay.allCases)
}

