//
//  AlertStatus.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of AlertStatusRequest and AlertStatusResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/AlertStatusRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/AlertStatusResponse.java
//

import Foundation

/// Request current alert status from the pump.
public class AlertStatusRequest: Message {
    public static var props = MessageProps(
        opCode: 68,
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

/// Response containing active alerts represented as a bitmask.
public class AlertStatusResponse: Message {
    public static var props = MessageProps(
        opCode: 69,
        size: 8,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var intMap: UInt64
    public var alerts: Set<AlertResponseType>

    public required init(cargo: Data) {
        self.cargo = cargo
        self.intMap = Bytes.readUint64(cargo, 0)
        self.alerts = AlertResponseType.fromBitmask(intMap)
    }

    public init(intMap: UInt64) {
        self.cargo = Bytes.toUint64(intMap)
        self.intMap = intMap
        self.alerts = AlertResponseType.fromBitmask(intMap)
    }

    /// Alert types encoded in the response bitmask.
    public enum AlertResponseType: Int, CaseIterable, Comparable {
        case LOW_INSULIN_ALERT = 0
        case USB_CONNECTION_ALERT = 1
        case LOW_POWER_ALERT = 2
        case LOW_POWER_ALERT2 = 3
        case DATA_ERROR_ALERT = 4
        case AUTO_OFF_ALERT = 5
        case MAX_BASAL_RATE_ALERT = 6
        case POWER_SOURCE_ALERT = 7
        case MIN_BASAL_ALERT = 8
        case CONNECTION_ERROR_ALERT = 9
        case CONNECTION_ERROR_ALERT2 = 10
        case INCOMPLETE_BOLUS_ALERT = 11
        case INCOMPLETE_TEMP_RATE_ALERT = 12
        case INCOMPLETE_CARTRIDGE_CHANGE_ALERT = 13
        case INCOMPLETE_FILL_TUBING_ALERT = 14
        case INCOMPLETE_FILL_CANNULA_ALERT = 15
        case INCOMPLETE_SETTING_ALERT = 16
        case LOW_INSULIN_ALERT2 = 17
        case MAX_BASAL_ALERT = 18
        case LOW_TRANSMITTER_ALERT = 19
        case TRANSMITTER_ALERT = 20
        case DEFAULT_ALERT_21 = 21
        case SENSOR_EXPIRING_ALERT = 22
        case PUMP_REBOOTING_ALERT = 23
        case DEVICE_CONNECTION_ERROR = 24
        case CGM_GRAPH_REMOVED = 25
        case MIN_BASAL_ALERT2 = 26
        case INCOMPLETE_CALIBRATION = 27
        case CALIBRATION_TIMEOUT = 28
        case INVALID_TRANSMITTER_ID = 29
        case DEFAULT_ALERT_30 = 30
        case DEFAULT_ALERT_32 = 32
        case BUTTON_ALERT = 33
        case QUICK_BOLUS_ALERT = 34
        case BASAL_IQ_ALERT = 35
        case DEFAULT_ALERT_36 = 36
        case DEFAULT_ALERT_37 = 37
        case DEFAULT_ALERT_38 = 38
        case TRANSMITTER_END_OF_LIFE = 39
        case CGM_ERROR = 40
        case CGM_ERROR2 = 41
        case CGM_ERROR3 = 42
        case DEFAULT_ALERT_43 = 43
        case TRANSMITTER_EXPIRING_ALERT = 44
        case TRANSMITTER_EXPIRING_ALERT2 = 45
        case TRANSMITTER_EXPIRING_ALERT3 = 46
        case DEFAULT_ALERT_47 = 47
        case CGM_UNAVAILABLE = 48
        case FILL_TUBING_STILL_IN_PROGRESS = 49
        case DEFAULT_ALERT_50 = 50
        case DEFAULT_ALERT_51 = 51
        case DEFAULT_ALERT_52 = 52
        case DEFAULT_ALERT_53 = 53
        case DEVICE_PAIRED = 54
        case DEFAULT_ALERT_55 = 55
        case DEFAULT_ALERT_56 = 56
        case DEFAULT_ALERT_57 = 57
        case DEFAULT_ALERT_58 = 58
        case DEFAULT_ALERT_59 = 59
        case DEFAULT_ALERT_60 = 60
        case DEFAULT_ALERT_61 = 61
        case DEFAULT_ALERT_62 = 62
        case DEFAULT_ALERT_63 = 63

        public static func < (lhs: AlertResponseType, rhs: AlertResponseType) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }

        /// Returns a set of alerts encoded in the provided bitmask.
        public static func fromBitmask(_ intMap: UInt64) -> Set<AlertResponseType> {
            var current = Set<AlertResponseType>()
            for type in AlertResponseType.allCases {
                if (intMap >> type.rawValue) & 1 == 1 {
                    current.insert(type)
                }
            }
            return current
        }
    }
}


