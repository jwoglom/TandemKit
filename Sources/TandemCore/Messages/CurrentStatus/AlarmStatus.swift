import Foundation

/**
 * Request current alarm status from the pump.
 */
public class AlarmStatusRequest: PumpRequest {
    public typealias Response = AlarmStatusResponse

    public static let props = MessageProps(
        opCode: 70,
        size: 0,
        type: .Request,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }

    public var description: String {
        "AlarmStatusRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/**
 * Response containing active alarms represented as a bitmask.
 */
public class AlarmStatusResponse: Message, NotificationMessage {
    public static let props = MessageProps(
        opCode: 71,
        size: 8,
        type: .Response,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var intMap: UInt64
    public var alarms: Set<AlarmResponseType>

    public required init(cargo: Data) {
        self.cargo = cargo
        intMap = Bytes.readUint64(cargo, 0)
        alarms = AlarmResponseType.fromBitmask(intMap)
    }

    public init(intMap: UInt64) {
        cargo = Bytes.toUint64(intMap)
        self.intMap = intMap
        alarms = AlarmResponseType.fromBitmask(intMap)
    }

    /// Alarm types encoded in the response bitmask.
    public enum AlarmResponseType: Int, CaseIterable, Comparable, NotificationEnum {
        /// Tandem firmware name: Alarm_DELIVERY_NOT_STOPPED
        case CARTRIDGE_ALARM_DELIVERY_NOT_STOPPED = 0
        /// Tandem firmware name: Alarm_SPOOL_MOVE
        case CARTRIDGE_ALARM_SPOOL_MOVE = 1
        /// Tandem firmware name: Alarm_OCCLUSION
        case OCCLUSION_ALARM = 2
        /// Tandem firmware name: Alarm_NO_STARTUP_ACK
        case PUMP_RESET_ALARM = 3
        /// Tandem firmware name: Alarm_OBE
        case OBE_ALARM = 4
        /// Tandem firmware name: Alarm_P2
        case CARTRIDGE_ALARM_P2 = 5
        /// Tandem firmware name: Alarm_VENT_NOT_WORKING
        case CARTRIDGE_ALARM_VENT_NOT_WORKING = 6
        /// Tandem firmware name: Alarm_AUTO_OFF_TRIGGERED
        case AUTO_OFF_ALARM = 7
        /// Tandem firmware name: Alarm_LIQ_OUT
        case EMPTY_CARTRIDGE_ALARM = 8
        /// Tandem firmware name: Alarm_LIQ_EX
        case CARTRIDGE_ALARM_LIQ_EX = 9
        /// Tandem firmware name: Alarm_TEMPERATURE_OOR
        case TEMPERATURE_ALARM = 10
        /// Tandem firmware name: Alarm_TEMPERATURE_XDCR
        case TEMPERATURE_ALARM2 = 11
        /// Tandem firmware name: Alarm_LIPO_VERY_LOW
        case BATTERY_SHUTDOWN_ALARM = 12
        /// Tandem firmware name: Alarm_FLUID_CHANGE_obsolete
        case DEFAULT_ALARM_13 = 13
        /// Tandem firmware name: Alarm_USER_DATE_INVALID
        case INVALID_DATE_ALARM = 14
        /// Tandem firmware name: Alarm_LIPO_TEMPERATURE
        case TEMPERATURE_ALARM3 = 15
        /// Tandem firmware name: Alarm_DELIVERY_REQUEST_FAIL
        case CARTRIDGE_ALARM_DELIVERY_REQUEST_FAIL = 16
        /// Tandem firmware name: Alarm_CANT_HOME_obsolete
        case DEFAULT_ALARM_17 = 17
        /// Tandem firmware name: Alarm_STATE_SUSPEND
        case RESUME_PUMP_ALARM = 18
        /// Tandem firmware name: Alarm_UNICORN_DO_NOT_USE
        case DEFAULT_ALARM_19 = 19
        /// Tandem firmware name: Alarm_MOTOR_PICASSO
        case CARTRIDGE_ALARM_MOTOR_PICASSO = 20
        /// Tandem firmware name: Alarm_PRESSURE_DISAGREE
        case ALTITUDE_ALARM = 21
        /// Tandem firmware name: Alarm_STUCK_BUTTON
        case STUCK_BUTTON_ALARM = 22
        /// Tandem firmware name: Alarm_GENERIC
        case RESUME_PUMP_ALARM2 = 23
        /// Tandem firmware name: Alarm_PATM
        case ATMOSPHERIC_PRESSURE_OUT_OF_RANGE_ALARM = 24
        /// Tandem firmware name: Alarm_CART_REMOVED
        case CARTRIDGE_REMOVED_ALARM = 25
        /// Tandem firmware name: Alarm_OCCLUSION_THE_YOUNGER
        case OCCLUSION_ALARM2 = 26
        /// Tandem firmware name: Alarm_UNUSED_1
        case DEFAULT_ALARM_27 = 27
        /// Tandem firmware name: Alarm_UNUSED_2
        case DEFAULT_ALARM_28 = 28
        /// Tandem firmware name: Alarm_MOTOR_CART_RANGE_LOW
        case CARTRIDGE_ALARM_MOTOR_CART_RANGE_LOW = 29
        /// Tandem firmware name: Alarm_MOTOR_STALL
        case CARTRIDGE_ALARM_MOTOR_STALL = 30
        /// Tandem firmware name: Alarm_MOTOR_VENT_STALL
        case CARTRIDGE_ALARM_MOTOR_VENT_STALL = 31
        /// Tandem firmware name: Alarm_NO_CARTRIDGE_DETECTED
        case NO_CARTRIDGE_DETECTED_ALARM = 32
        /// Tandem firmware name: Alarm_LIPO_INSUFF_POWER
        case LIPO_INSUFF_POWER_ALARM = 33
        /// Tandem firmware name: Alarm_MOTOR_HALL_EFFECT_FAIL
        case CARTRIDGE_ALARM_MOTOR_HALL_EFFECT_FAIL = 34
        /// Tandem firmware name: Alarm_MOTOR_FAILURE_MODE
        case MOTOR_FAILURE_MODE_ALARM = 35
        /// Tandem firmware name: Alarm_MOTOR_PRIME_STALL_OBE
        case MOTOR_PRIME_STALL_OBE_ALARM = 36
        /// Tandem firmware name: Alarm_AUXCPU_SYSTEM_RESET
        case AUXCPU_SYSTEM_RESET_ALARM = 37
        /// Tandem firmware name: NUM_ALARMS
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
            lhs.rawValue < rhs.rawValue
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

        public var id: Int { rawValue }

        /// Whether the alarm has an associated user-facing description.
        public var isKnownAlarm: Bool { notificationDescription != nil && !(notificationDescription ?? "").isEmpty }

        public var notificationDescription: String? {
            switch self {
            case .CARTRIDGE_ALARM_DELIVERY_NOT_STOPPED,
                 .CARTRIDGE_ALARM_SPOOL_MOVE,
                 .CARTRIDGE_ALARM_P2,
                 .CARTRIDGE_ALARM_VENT_NOT_WORKING,
                 .CARTRIDGE_ALARM_LIQ_EX,
                 .CARTRIDGE_ALARM_DELIVERY_REQUEST_FAIL,
                 .CARTRIDGE_ALARM_MOTOR_PICASSO,
                 .CARTRIDGE_ALARM_MOTOR_CART_RANGE_LOW,
                 .CARTRIDGE_ALARM_MOTOR_STALL,
                 .CARTRIDGE_ALARM_MOTOR_VENT_STALL,
                 .CARTRIDGE_ALARM_MOTOR_HALL_EFFECT_FAIL:
                return "There is an issue with the cartridge and it needs to be replaced."
            case .OCCLUSION_ALARM,
                 .OCCLUSION_ALARM2:
                return "An occlusion has occurred. Please check your pump site and tubing and restart insulin delivery."
            case .PUMP_RESET_ALARM:
                return "The pump was reset. IOB has been reset to 0 and CGM may need to be re-activated."
            case .AUTO_OFF_ALARM:
                return "Pump will stop delivering insulin automatically soon because no user activity has occurred and the auto-off setting is enabled."
            case .EMPTY_CARTRIDGE_ALARM:
                return "Cartridge is out of insulin and insulin delivery cannot occur. Please fill a new cartridge."
            case .TEMPERATURE_ALARM,
                 .TEMPERATURE_ALARM2,
                 .TEMPERATURE_ALARM3:
                return "Pump temperature is out of range and insulin cannot be safely delivered."
            case .BATTERY_SHUTDOWN_ALARM:
                return "Pump battery level is critically low and the device will shut down. Please charge pump immediately."
            case .INVALID_DATE_ALARM:
                return "The pump's configured date is invalid."
            case .RESUME_PUMP_ALARM,
                 .RESUME_PUMP_ALARM2:
                return "Insulin delivery is currently off. Please restart insulin delivery soon."
            case .ALTITUDE_ALARM:
                return "Pump altitude is out of range and insulin cannot be safely delivered."
            case .STUCK_BUTTON_ALARM:
                return "The pump button may be stuck or has been pressed for too long a period of time."
            case .ATMOSPHERIC_PRESSURE_OUT_OF_RANGE_ALARM:
                return "Pump atmospheric pressure is out of range and insulin cannot be safely delivered."
            case .CARTRIDGE_REMOVED_ALARM:
                return "The cartridge was removed from the pump. Please fill a new cartridge."
            default:
                return nil
            }
        }
    }

    public var notificationCount: Int { alarms.count }

    public var notificationIds: Set<Int> {
        Set(alarms.filter { $0.isKnownAlarm }.map(\.rawValue))
    }

    public var description: String {
        "AlarmStatusResponse(cargo=\(cargo.hexadecimalString), alarms=\(alarms), intMap=\(intMap))"
    }
}
