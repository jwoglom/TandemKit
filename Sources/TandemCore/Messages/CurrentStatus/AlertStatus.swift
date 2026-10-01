import Foundation

/// Request current alert status from the pump.
public class AlertStatusRequest: PumpRequest {
    public typealias Response = AlertStatusResponse

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
        /// Tandem firmware name: oaAlert_LIQ_LOW
        case LOW_INSULIN_ALERT = 0
        /// Tandem firmware name: oaAlert_USB_INSUFF_CURRENT
        case USB_CONNECTION_ALERT = 1
        /// Tandem firmware name: aaAlert_LIPO_LOW
        case LOW_POWER_ALERT = 2
        /// Tandem firmware name: aaAlert_LIPO_VERY_LOW
        case LOW_POWER_ALERT2 = 3
        /// Tandem firmware name: oaAlert_NVM
        case DATA_ERROR_ALERT = 4
        /// Tandem firmware name: oaAlert_AUTO_OFF
        case AUTO_OFF_ALERT = 5
        /// Tandem firmware name: oaAlert_BASAL_RATE_LIMIT
        case MAX_BASAL_RATE_ALERT = 6
        /// Tandem firmware name: oaAlert_LIPO_CANT_CHARGE
        case POWER_SOURCE_ALERT = 7
        /// Tandem firmware name: oaAlert_BASAL_RATE_TOO_LOW
        case MIN_BASAL_ALERT = 8
        /// Tandem firmware name: aaAlert_USB_NOT_RECOGNIZED
        case CONNECTION_ERROR_ALERT = 9
        /// Tandem firmware name: aaAlert_BAD_PC_COM
        case CONNECTION_ERROR_ALERT2 = 10
        /// Tandem firmware name: oaAlert_INCOMPLETE_BOLUS
        case INCOMPLETE_BOLUS_ALERT = 11
        /// Tandem firmware name: oaAlert_INCOMPLETE_TEMP_RATE
        case INCOMPLETE_TEMP_RATE_ALERT = 12
        /// Tandem firmware name: oaAlert_INCOMPLETE_CARTRIDGE
        case INCOMPLETE_CARTRIDGE_CHANGE_ALERT = 13
        /// Tandem firmware name: oaAlert_INCOMPLETE_TUBING
        case INCOMPLETE_FILL_TUBING_ALERT = 14
        /// Tandem firmware name: oaAlert_INCOMPLETE_CANNULA
        case INCOMPLETE_FILL_CANNULA_ALERT = 15
        /// Tandem firmware name: oaAlert_INCOMPLETE_SETTING
        case INCOMPLETE_SETTING_ALERT = 16
        /// Tandem firmware name: oaAlert_LIQ_VERY_LOW
        case LOW_INSULIN_ALERT2 = 17
        /// Tandem firmware name: oaAlert_ABS_MAX_BASAL_LIMIT
        case MAX_BASAL_ALERT = 18
        /// Tandem firmware name: aaAlert_STUCK_BUTTON
        case LOW_TRANSMITTER_ALERT = 19
        /// Tandem firmware name: aaAlert_CGM_SUPPORT_PACKAGE_ERROR
        case TRANSMITTER_ALERT = 20
        /// Tandem firmware name: aaAlert_FSL2_SUPPORT_PACKAGE_ERROR
        case FSL2_SUPPORT_PACKAGE_ERROR_ALERT = 21
        /// Tandem firmware name: aaAlert_STK_CSP_REQ
        case SENSOR_EXPIRING_ALERT = 22
        /// Tandem firmware name: oaAlert_USB_SHUTDOWN
        case PUMP_REBOOTING_ALERT = 23
        /// Tandem firmware name: aaAlert_CGM_MANY_SENSORS
        case DEVICE_CONNECTION_ERROR = 24
        /// Tandem firmware name: aaAlert_CGM_GRAPH_REMOVAL
        case CGM_GRAPH_REMOVED = 25
        /// Tandem firmware name: oaAlert_BASAL_RATE_LOW
        case MIN_BASAL_ALERT2 = 26
        /// Tandem firmware name: aaAlert_CGM_INCOMPLETE_CAL
        case INCOMPLETE_CALIBRATION = 27
        /// Tandem firmware name: aaAlert_CGM_CAL_TIMEOUT
        case CALIBRATION_TIMEOUT = 28
        /// Tandem firmware name: aaAlert_CGM_INVALID_TX_ID
        case INVALID_TRANSMITTER_ID = 29
        /// Tandem firmware name: aaAlert_DEBUG_INFO_DECLARED
        case DEBUG_INFO_DECLARED_ALERT = 30
        /// Tandem firmware name: oaAlert_OPEN_SESAME
        case OPEN_SESAME_ALERT = 32
        /// Tandem firmware name: aaAlert_QUICK_BOLUS_ABORT
        case BUTTON_ALERT = 33
        /// Tandem firmware name: aaAlert_MANY_FAILED_QUICK_BOLUS
        case QUICK_BOLUS_ALERT = 34
        /// Tandem firmware name: Alert_AP_ALERT
        case BASAL_IQ_ALERT = 35
        /// Tandem firmware name: aaAlert_STK_EXCHANGE_REQ
        case STK_EXCHANGE_REQ_ALERT = 36
        /// Tandem firmware name: aaAlert_STK_ODYSSEY_REQ
        case STK_ODYSSEY_REQ_ALERT = 37
        /// Tandem firmware name: aaAlert_STK_INVALID
        case STK_INVALID_ALERT = 38
        /// Tandem firmware name: aaAlert_CGM_TX_EOL
        case TRANSMITTER_END_OF_LIFE = 39
        /// Tandem firmware name: aaAlert_CGM_BLE_SD
        case CGM_ERROR = 40
        /// Tandem firmware name: aaAlert_CGM_BLE_HW_WATCHDOG
        case CGM_ERROR2 = 41
        /// Tandem firmware name: aaAlert_CGM_BLE_HW_TIMEOUT
        case CGM_ERROR3 = 42
        /// Tandem firmware name: aaAlert_CGM_INCOMPATIBLE
        case CGM_INCOMPATIBLE_ALERT = 43
        /// Tandem firmware name: aaAlert_CGM_TX_EXPIRING_SOON_1
        case TRANSMITTER_EXPIRING_ALERT = 44
        /// Tandem firmware name: aaAlert_CGM_TX_EXPIRING_SOON_2
        case TRANSMITTER_EXPIRING_ALERT2 = 45
        /// Tandem firmware name: aaAlert_CGM_TX_EXPIRING_STARTUP
        case TRANSMITTER_EXPIRING_ALERT3 = 46
        /// Tandem firmware name: oaAlert_TZ_INCOMPLETE_SETTING
        case TZ_INCOMPLETE_SETTING_ALERT = 47
        /// Tandem firmware name: aaAlert_CGM_NO_READINGS
        case CGM_UNAVAILABLE = 48
        /// Tandem firmware name: aaAlert_PRIME_LIMIT
        case FILL_TUBING_STILL_IN_PROGRESS = 49
        /// Tandem firmware name: aaAlert_TZ_HYPER_LIGHT
        case TZ_HYPER_LIGHT_ALERT = 50
        /// Tandem firmware name: aaAlert_TZ_HYPO_LIGHT
        case CONTROL_IQ_LOW = 51
        /// Tandem firmware name: aaAlert_TZ_IIDM
        case TZ_IIDM_ALERT = 52
        /// Tandem firmware name: aaAlert_BLE_CRASH_DUMP
        case BLE_CRASH_DUMP_ALERT = 53
        /// Tandem firmware name: aaAlert_MH_PAIRED
        case DEVICE_PAIRED = 54
        /// Tandem firmware name: aaAlert_BLE_HW_ERROR
        case BLE_HW_ERROR_ALERT = 55
        /// Tandem firmware name: aaAlert_USER_SET_MAX_BASAL
        case USER_SET_MAX_BASAL_ALERT = 56
        /// Tandem firmware name: aaAlert_SENSOR
        case SENSOR_ALERT = 57
        /// Tandem firmware name: aaAlert_COM_LOG_ERROR_LOGGED
        case COM_LOG_ERROR_LOGGED_ALERT = 58
        /// Tandem firmware name: alert_FCL_AUTOMATION_OFF
        case FCL_AUTOMATION_OFF_ALERT = 59
        /// Tandem firmware name: oaAlert_CONTROLLER_CONNECTION_LOST
        case CONTROLLER_CONNECTION_LOST_ALERT = 60
        /// Tandem firmware name: aaAlert_LIPO_SUPER_LOW
        case LIPO_SUPER_LOW_ALERT = 61
        /// Tandem firmware name: aaAlert_LIPO_INSUFF_POWER
        case LIPO_INSUFF_POWER_ALERT = 62
        /// Tandem firmware name: oaAlert_BTLE_PAIRING_TIMEOUT
        case BTLE_PAIRING_TIMEOUT_ALERT = 63

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
            case .CONTROL_IQ_LOW:
                return "Control-IQ has reduced basal insulin delivery due to a low or predicted low glucose value."
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
