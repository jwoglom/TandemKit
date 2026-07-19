import Foundation

/**
 * Request current alarm status from the pump.
 */
public class AlarmStatusRequest: Message {
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
        case CARTRIDGE_ALARM = 0
        case CARTRIDGE_ALARM_2 = 1
        case OCCLUSION_ALARM = 2
        case PUMP_RESET_ALARM = 3
        case DEFAULT_ALARM_4 = 4
        case CARTRIDGE_ALARM_3 = 5
        case CARTRIDGE_ALARM_4 = 6
        case AUTO_OFF_ALARM = 7
        case EMPTY_CARTRIDGE_ALARM = 8
        case CARTRIDGE_ALARM_5 = 9
        case TEMPERATURE_ALARM = 10
        case TEMPERATURE_ALARM2 = 11
        case BATTERY_SHUTDOWN_ALARM = 12
        case DEFAULT_ALARM_13 = 13
        case INVALID_DATE_ALARM = 14
        case TEMPERATURE_ALARM3 = 15
        case CARTRIDGE_ALARM_6 = 16
        case DEFAULT_ALARM_17 = 17
        case RESUME_PUMP_ALARM = 18
        case DEFAULT_ALARM_19 = 19
        case CARTRIDGE_ALARM_7 = 20
        case ALTITUDE_ALARM = 21
        case STUCK_BUTTON_ALARM = 22
        case RESUME_PUMP_ALARM2 = 23
        case ATMOSPHERIC_PRESSURE_OUT_OF_RANGE_ALARM = 24
        case CARTRIDGE_REMOVED_ALARM = 25
        case OCCLUSION_ALARM2 = 26
        case DEFAULT_ALARM_27 = 27
        case DEFAULT_ALARM_28 = 28
        case CARTRIDGE_ALARM_10 = 29
        case CARTRIDGE_ALARM_11 = 30
        case CARTRIDGE_ALARM_12 = 31
        case DEFAULT_ALARM_32 = 32
        case DEFAULT_ALARM_33 = 33
        case CARTRIDGE_ALARM_34 = 34
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
            lhs.rawValue < rhs.rawValue
        }

        /// Groups of alarms that the pump acknowledges together: dismissing any one
        /// member causes the pump to clear the entire group on our behalf. Because
        /// such alarms describe a single underlying condition, the notification UI
        /// condenses them into one row (e.g. "Alarm: RESUME_PUMP_ALARM,
        /// RESUME_PUMP_ALARM2") and dismisses only the representative.
        ///
        /// Each inner array lists the members in display order; the first element is
        /// the representative dismissed on the user's behalf. See
        /// `NotificationCondensationGroup`.
        public static let condensationGroups: [[AlarmResponseType]] = [
            [.RESUME_PUMP_ALARM, .RESUME_PUMP_ALARM2]
        ]

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
            case .CARTRIDGE_ALARM,
                 .CARTRIDGE_ALARM_2,
                 .CARTRIDGE_ALARM_3,
                 .CARTRIDGE_ALARM_4,
                 .CARTRIDGE_ALARM_5,
                 .CARTRIDGE_ALARM_6,
                 .CARTRIDGE_ALARM_7,
                 .CARTRIDGE_ALARM_10,
                 .CARTRIDGE_ALARM_11,
                 .CARTRIDGE_ALARM_12,
                 .CARTRIDGE_ALARM_34:
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
