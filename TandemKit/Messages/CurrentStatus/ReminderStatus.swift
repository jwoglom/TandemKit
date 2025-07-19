//
//  ReminderStatus.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of ReminderStatusRequest and ReminderStatusResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/ReminderStatusRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/ReminderStatusResponse.java
//

import Foundation

/// Request the bitmask of active reminders.
public class ReminderStatusRequest: Message {
    public static var props = MessageProps(
        opCode: 72,
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

/// Response containing the reminders bitmask.
public class ReminderStatusResponse: Message {
    public static var props = MessageProps(
        opCode: 73,
        size: 8,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var intMap: UInt64

    public required init(cargo: Data) {
        self.cargo = cargo
        self.intMap = Bytes.readUint64(cargo, 0)
    }

    public init(intMap: UInt64) {
        self.cargo = Bytes.toUint64(intMap)
        self.intMap = intMap
    }

    /// Decode the set of reminder types from the bitmask.
    public var reminders: Set<ReminderType> { return ReminderType.fromBitmask(intMap) }

    /// Reminder type bit positions.
    public enum ReminderType: Int, CaseIterable {
        case LOW_BG_REMINDER = 0
        case HIGH_BG_REMINDER = 1
        case SITE_CHANGE_REMINDER = 2
        case MISSED_MEAL_REMINDER = 3
        case MISSED_MEAL_REMINDER1 = 4
        case MISSED_MEAL_REMINDER2 = 5
        case MISSED_MEAL_REMINDER3 = 6
        case AFTER_BOLUS_BG_REMINDER = 7
        case ADDITIONAL_BOLUS_REMINDER = 8
        case DEFAULT_REMINDER_9 = 9
        case DEFAULT_REMINDER_10 = 10
        case DEFAULT_REMINDER_11 = 11
        case DEFAULT_REMINDER_12 = 12
        case DEFAULT_REMINDER_13 = 13
        case DEFAULT_REMINDER_14 = 14
        case DEFAULT_REMINDER_15 = 15
        case DEFAULT_REMINDER_16 = 16
        case DEFAULT_REMINDER_17 = 17
        case DEFAULT_REMINDER_18 = 18
        case DEFAULT_REMINDER_19 = 19
        case DEFAULT_REMINDER_20 = 20
        case DEFAULT_REMINDER_21 = 21
        case DEFAULT_REMINDER_22 = 22
        case DEFAULT_REMINDER_23 = 23
        case DEFAULT_REMINDER_24 = 24
        case DEFAULT_REMINDER_25 = 25
        case DEFAULT_REMINDER_26 = 26
        case DEFAULT_REMINDER_27 = 27
        case DEFAULT_REMINDER_28 = 28
        case DEFAULT_REMINDER_29 = 29
        case DEFAULT_REMINDER_30 = 30
        case DEFAULT_REMINDER_31 = 31
        case DEFAULT_REMINDER_32 = 32
        case DEFAULT_REMINDER_33 = 33
        case DEFAULT_REMINDER_34 = 34
        case DEFAULT_REMINDER_35 = 35
        case DEFAULT_REMINDER_36 = 36
        case DEFAULT_REMINDER_37 = 37
        case DEFAULT_REMINDER_38 = 38
        case DEFAULT_REMINDER_39 = 39
        case DEFAULT_REMINDER_40 = 40
        case DEFAULT_REMINDER_41 = 41
        case DEFAULT_REMINDER_42 = 42
        case DEFAULT_REMINDER_43 = 43
        case DEFAULT_REMINDER_44 = 44
        case DEFAULT_REMINDER_45 = 45
        case DEFAULT_REMINDER_46 = 46
        case DEFAULT_REMINDER_47 = 47
        case DEFAULT_REMINDER_48 = 48
        case DEFAULT_REMINDER_49 = 49
        case DEFAULT_REMINDER_50 = 50
        case DEFAULT_REMINDER_51 = 51
        case DEFAULT_REMINDER_52 = 52
        case DEFAULT_REMINDER_53 = 53
        case DEFAULT_REMINDER_54 = 54
        case DEFAULT_REMINDER_55 = 55
        case DEFAULT_REMINDER_56 = 56
        case DEFAULT_REMINDER_57 = 57
        case DEFAULT_REMINDER_58 = 58
        case DEFAULT_REMINDER_59 = 59
        case DEFAULT_REMINDER_60 = 60
        case DEFAULT_REMINDER_61 = 61
        case DEFAULT_REMINDER_62 = 62
        case DEFAULT_REMINDER_63 = 63

        public static func fromBitmask(_ bitmask: UInt64) -> Set<ReminderType> {
            var set = Set<ReminderType>()
            for r in ReminderType.allCases {
                if (bitmask >> r.rawValue) & 1 == 1 { set.insert(r) }
            }
            return set
        }
    }
}

