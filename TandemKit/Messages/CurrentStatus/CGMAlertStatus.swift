//
//  CGMAlertStatus.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of CGMAlertStatusRequest and CGMAlertStatusResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/CGMAlertStatusRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/CGMAlertStatusResponse.java
//

import Foundation

/// Request current CGM alerts from the pump.
public class CGMAlertStatusRequest: Message {
    public static var props = MessageProps(
        opCode: 74,
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

/// Response describing active CGM alerts via bitmask.
public class CGMAlertStatusResponse: Message {
    public static var props = MessageProps(
        opCode: 75,
        size: 8,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var intMap: UInt64
    public var alerts: Set<CGMAlert>

    public required init(cargo: Data) {
        self.cargo = cargo
        self.intMap = Bytes.readUint64(cargo, 0)
        self.alerts = CGMAlert.fromBitmask(intMap)
    }

    public init(intMap: UInt64) {
        self.cargo = Bytes.toUint64(intMap)
        self.intMap = intMap
        self.alerts = CGMAlert.fromBitmask(intMap)
    }

    /// CGM alert bit positions.
    public enum CGMAlert: Int, CaseIterable, Comparable {
        case DEFAULT_CGM_ALERT_0 = 0
        case FIXED_LOW_CGM_ALERT = 1
        case HIGH_CGM_ALERT = 2
        case LOW_CGM_ALERT = 3
        case CALIBRATION_REQUEST_CGM_ALERT = 4
        case RISE_CGM_ALERT = 5
        case RAPID_RISE_CGM_ALERT = 6
        case FALL_CGM_ALERT = 7
        case RAPID_FALL_CGM_ALERT = 8
        case LOW_CALIBRATION_ERROR_CGM_ALERT = 9
        case HIGH_CALIBRATION_ERROR_CGM_ALERT = 10
        case SENSOR_FAILED_CGM_ALERT = 11
        case SENSOR_EXPIRING_CGM_ALERT = 12
        case SENSOR_EXPIRED_CGM_ALERT = 13
        case OUT_OF_RANGE_CGM_ALERT = 14
        case DEFAULT_CGM_ALERT_15 = 15
        case FIRST_START_CALIBRATION_CGM_ALERT = 16
        case SECOND_START_CALIBRATION_CGM_ALERT = 17
        case CALIBRATION_REQUIRED_CGM_ALERT = 18
        case LOW_TRANSMITTER_CGM_ALERT = 19
        case TRANSMITTER_CGM_ALERT = 20
        case DEFAULT_CGM_ALERT_21 = 21
        case SENSOR_EXPIRING_CGM_ALERT2 = 22
        case DEFAULT_CGM_ALERT_23 = 23
        case DEFAULT_CGM_ALERT_24 = 24
        case SENSOR_REUSE = 25
        case DEFAULT_CGM_ALERT_26 = 26
        case DEFAULT_CGM_ALERT_27 = 27
        case DEFAULT_CGM_ALERT_28 = 28
        case DEFAULT_CGM_ALERT_29 = 29
        case DEFAULT_CGM_ALERT_30 = 30
        case DEFAULT_CGM_ALERT_31 = 31
        case DEFAULT_CGM_ALERT_32 = 32
        case DEFAULT_CGM_ALERT_33 = 33
        case DEFAULT_CGM_ALERT_34 = 34
        case DEFAULT_CGM_ALERT_35 = 35
        case DEFAULT_CGM_ALERT_36 = 36
        case DEFAULT_CGM_ALERT_37 = 37
        case DEFAULT_CGM_ALERT_38 = 38
        case DEFAULT_CGM_ALERT_39 = 39
        case DEFAULT_CGM_ALERT_40 = 40
        case DEFAULT_CGM_ALERT_41 = 41
        case DEFAULT_CGM_ALERT_42 = 42
        case DEFAULT_CGM_ALERT_43 = 43
        case DEFAULT_CGM_ALERT_44 = 44
        case DEFAULT_CGM_ALERT_45 = 45
        case DEFAULT_CGM_ALERT_46 = 46
        case DEFAULT_CGM_ALERT_47 = 47
        case DEFAULT_CGM_ALERT_48 = 48
        case DEFAULT_CGM_ALERT_49 = 49
        case DEFAULT_CGM_ALERT_50 = 50
        case DEFAULT_CGM_ALERT_51 = 51
        case DEFAULT_CGM_ALERT_52 = 52
        case DEFAULT_CGM_ALERT_53 = 53
        case DEFAULT_CGM_ALERT_55 = 55
        case DEFAULT_CGM_ALERT_56 = 56
        case DEFAULT_CGM_ALERT_57 = 57
        case DEFAULT_CGM_ALERT_58 = 58
        case DEFAULT_CGM_ALERT_59 = 59
        case DEFAULT_CGM_ALERT_60 = 60
        case DEFAULT_CGM_ALERT_61 = 61
        case DEFAULT_CGM_ALERT_62 = 62
        case DEFAULT_CGM_ALERT_63 = 63

        public static func < (lhs: CGMAlert, rhs: CGMAlert) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }

        /// Decode a set of alerts from the provided bitmask.
        public static func fromBitmask(_ bitmask: UInt64) -> Set<CGMAlert> {
            var set = Set<CGMAlert>()
            for alert in CGMAlert.allCases {
                if (bitmask >> alert.rawValue) & 1 == 1 {
                    set.insert(alert)
                }
            }
            return set
        }
    }
}

