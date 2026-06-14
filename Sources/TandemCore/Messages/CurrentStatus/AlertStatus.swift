import Foundation

/// Request current alert status from the pump.
public class AlertStatusRequest: Message {
    public static let props = MessageProps(
        opCode: 68,
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
        "AlertStatusRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response containing active alerts represented as a bitmask.
public class AlertStatusResponse: Message, NotificationMessage {
    public static let props = MessageProps(
        opCode: 69,
        size: 8,
        type: .Response,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var intMap: UInt64
    public var alerts: Set<AlertResponseType>

    public required init(cargo: Data) {
        self.cargo = cargo
        intMap = Bytes.readUint64(cargo, 0)
        alerts = AlertResponseType.fromBitmask(intMap)
    }

    public init(intMap: UInt64) {
        cargo = Bytes.toUint64(intMap)
        self.intMap = intMap
        alerts = AlertResponseType.fromBitmask(intMap)
    }

    /// Alert types encoded in the response bitmask.
    public enum AlertResponseType: Int, CaseIterable, Comparable, NotificationEnum {
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
            lhs.rawValue < rhs.rawValue
        }

        /// Basal-related alerts that can be automatically acknowledged when looping.
        /// These alerts indicate Control-IQ basal adjustments that are expected during closed-loop operation.
        public static let basalAlertsToIgnoreWhenLooping: Set<AlertResponseType> = [
            .MIN_BASAL_ALERT,
            .MIN_BASAL_ALERT2,
            .MAX_BASAL_ALERT,
            .MAX_BASAL_RATE_ALERT
        ]

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

        public var id: Int { rawValue }

        public var notificationDescription: String? {
            switch self {
            case .LOW_INSULIN_ALERT,
                 .LOW_INSULIN_ALERT2:
                return "Low amount of insulin remaining in the cartridge."
            case .USB_CONNECTION_ALERT:
                return "Pump is not charging over USB."
            case .LOW_POWER_ALERT,
                 .LOW_POWER_ALERT2:
                return "Power level is low and the pump needs to be charged."
            case .AUTO_OFF_ALERT:
                return "The pump is about to turn off due to the configured auto-off interval."
            case .MAX_BASAL_RATE_ALERT:
                return "The pump is delivering at the maximum allowed basal rate."
            case .POWER_SOURCE_ALERT:
                return "The power source provided is not able to charge the pump."
            case .MIN_BASAL_ALERT,
                 .MIN_BASAL_ALERT2:
                return "The pump is delivering at the minimum allowed basal rate."
            case .INCOMPLETE_BOLUS_ALERT:
                return "The bolus window was opened but a bolus was not started."
            case .INCOMPLETE_TEMP_RATE_ALERT:
                return "The temp rate window was opened but the temp rate was not started."
            case .INCOMPLETE_CARTRIDGE_CHANGE_ALERT:
                return "The cartridge change was started but not completed."
            case .INCOMPLETE_FILL_TUBING_ALERT:
                return "Fill tubing was started but not completed."
            case .INCOMPLETE_FILL_CANNULA_ALERT:
                return "Fill cannula was started but not completed."
            case .MAX_BASAL_ALERT:
                return "The maxmium basal was reached."
            case .LOW_TRANSMITTER_ALERT:
                return "The CGM transmitter battery is low."
            case .TRANSMITTER_ALERT:
                return "There is an alert from the CGM transmitter."
            case .SENSOR_EXPIRING_ALERT:
                return "The CGM sensor is expiring soon."
            case .PUMP_REBOOTING_ALERT:
                return "The pump is rebooting."
            case .CGM_GRAPH_REMOVED:
                return "It has been 24 hours since your last sensor session ended, so your current glucose reading now displays the last glucose value entered in the bolus calculator."
            case .INCOMPLETE_CALIBRATION:
                return "The CGM calibration was incomplete."
            case .CALIBRATION_TIMEOUT:
                return "The timeout was reached for CGM calibration."
            case .INVALID_TRANSMITTER_ID:
                return "The Dexcom G6 or G7 transmitter ID is invalid."
            case .BUTTON_ALERT:
                return "The pump button was held down for too long and is temporarily disabled to avoid accidental delivery of insulin."
            case .QUICK_BOLUS_ALERT:
                return "Quick bolus mode was entered but no bolus was started."
            case .BASAL_IQ_ALERT:
                return "BasalIQ has reduced basal insulin to avoid a low."
            case .TRANSMITTER_END_OF_LIFE:
                return "The CGM transmitter is reaching its end of life and cannot be used."
            case .CGM_ERROR,
                 .CGM_ERROR2,
                 .CGM_ERROR3:
                return "CGM error reported"
            case .TRANSMITTER_EXPIRING_ALERT,
                 .TRANSMITTER_EXPIRING_ALERT2,
                 .TRANSMITTER_EXPIRING_ALERT3:
                return "The CGM transmitter is expiring soon."
            case .CGM_UNAVAILABLE:
                return "The CGM is unavailable due to a problem with the sensor."
            case .FILL_TUBING_STILL_IN_PROGRESS:
                return "The fill tubing process is still in progress and was not completed."
            case .DEVICE_PAIRED:
                return "The pump was paired successfully to a Bluetooth device."
            default:
                return nil
            }
        }
    }

    public var notificationCount: Int { alerts.count }

    public var notificationIds: Set<Int> {
        Set(alerts.filter {
            let description = $0.notificationDescription ?? ""
            return !description.isEmpty
        }.map(\.rawValue))
    }

    public var description: String {
        "AlertStatusResponse(cargo=\(cargo.hexadecimalString), alerts=\(alerts), intMap=\(intMap))"
    }
}
