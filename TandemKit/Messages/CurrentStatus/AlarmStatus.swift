//
//  AlarmStatus.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representation of AlarmStatusRequest and AlarmStatusResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/AlarmStatusRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/AlarmStatusResponse.java
//

import Foundation

/**
 * Request current alarm status from the pump.
 */
public class AlarmStatusRequest: Message {
    public static var props = MessageProps(
        opCode: 70,
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

/**
 * Response containing active alarms represented as a bitmask.
 */
public class AlarmStatusResponse: Message {
    public static var props = MessageProps(
        opCode: 71,
        size: 8,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var intMap: UInt64
    public var alarms: Set<AlarmResponseType>

    public required init(cargo: Data) {
        self.cargo = cargo
        self.intMap = Bytes.readUint64(cargo, 0)
        self.alarms = AlarmResponseType.fromBitmask(intMap)
    }

    public init(intMap: UInt64) {
        self.cargo = Bytes.toUint64(intMap)
        self.intMap = intMap
        self.alarms = AlarmResponseType.fromBitmask(intMap)
    }

    /// Alarm types encoded in the response bitmask.
    public enum AlarmResponseType: Int, CaseIterable, Comparable {
        case CARTRIDGE_ALARM = 0
        case CARTRIDGE_ALARM2 = 1
        case OCCLUSION_ALARM = 2
        case PUMP_RESET_ALARM = 3
        case DEFAULT_ALARM_4 = 4
        case CARTRIDGE_ALARM3 = 5
        case CARTRIDGE_ALARM4 = 6
        case AUTO_OFF_ALARM = 7
        case EMPTY_CARTRIDGE_ALARM = 8
        case CARTRIDGE_ALARM5 = 9
        case TEMPERATURE_ALARM = 10
        case TEMPERATURE_ALARM2 = 11
        case BATTERY_SHUTDOWN_ALARM = 12
        case DEFAULT_ALARM_13 = 13
        case INVALID_DATE_ALARM = 14
        case TEMPERATURE_ALARM3 = 15
        case CARTRIDGE_ALARM6 = 16
        case DEFAULT_ALARM_17 = 17
        case RESUME_PUMP_ALARM = 18
        case DEFAULT_ALARM_19 = 19
        case CARTRIDGE_ALARM7 = 20
        case ALTITUDE_ALARM = 21
        case STUCK_BUTTON_ALARM = 22
        case RESUME_PUMP_ALARM2 = 23
        case ATMOSPHERIC_PRESSURE_OUT_OF_RANGE_ALARM = 24
        case CARTRIDGE_REMOVED_ALARM = 25
        case OCCLUSION_ALARM2 = 26
        case DEFAULT_ALARM_27 = 27
        case DEFAULT_ALARM_28 = 28
        case CARTRIDGE_ALARM10 = 29
        case CARTRIDGE_ALARM11 = 30
        case CARTRIDGE_ALARM12 = 31
        case DEFAULT_ALARM_32 = 32
        case DEFAULT_ALARM_33 = 33
        case DEFAULT_ALARM_34 = 34
        case DEFAULT_ALARM_35 = 35
        case DEFAULT_ALARM_36 = 36
        case DEFAULT_ALARM_37 = 37
        case DEFAULT_ALARM_38 = 38
        case DEFAULT_ALARM_39 = 39
        case DEFAULT_ALARM_40 = 40
        case DEFAULT_ALARM_41 = 41
        case DEFAULT_ALARM_42 = 42
        case DEFAULT_ALARM_43 = 43
        case DEFAULT_ALARM_44 = 44
        case DEFAULT_ALARM_45 = 45
        case DEFAULT_ALARM_46 = 46
        case DEFAULT_ALARM_47 = 47
        case DEFAULT_ALARM_48 = 48
        case DEFAULT_ALARM_49 = 49
        case DEFAULT_ALARM_50 = 50
        case DEFAULT_ALARM_51 = 51
        case DEFAULT_ALARM_52 = 52
        case DEFAULT_ALARM_53 = 53
        case DEFAULT_ALARM_54 = 54
        case DEFAULT_ALARM_55 = 55
        case DEFAULT_ALARM_56 = 56
        case DEFAULT_ALARM_57 = 57
        case DEFAULT_ALARM_58 = 58
        case DEFAULT_ALARM_59 = 59
        case DEFAULT_ALARM_60 = 60
        case DEFAULT_ALARM_61 = 61
        case DEFAULT_ALARM_62 = 62
        case DEFAULT_ALARM_63 = 63

        public static func < (lhs: AlarmResponseType, rhs: AlarmResponseType) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }

        /// Returns a set of alarms encoded in the provided bitmask.
        public static func fromBitmask(_ intMap: UInt64) -> Set<AlarmResponseType> {
            var current = Set<AlarmResponseType>()
            for type in AlarmResponseType.allCases {
                if (intMap >> type.rawValue) & 1 == 1 {
                    current.insert(type)
                }
            }
            return current
        }
    }
}
