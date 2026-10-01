import Foundation

/// Request current CGM alerts from the pump.
public class CGMAlertStatusRequest: PumpRequest {
    public typealias Response = CGMAlertStatusResponse

    public static let props = MessageProps(
        opCode: 74,
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
        "CGMAlertStatusRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response describing active CGM alerts via bitmask.
public class CGMAlertStatusResponse: Message, NotificationMessage {
    public static let props = MessageProps(
        opCode: 75,
        size: 8,
        type: .Response,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var intMap: UInt64
    public var alerts: Set<CGMAlert>

    public required init(cargo: Data) {
        self.cargo = cargo
        intMap = Bytes.readUint64(cargo, 0)
        alerts = CGMAlert.fromBitmask(intMap)
    }

    public init(intMap: UInt64) {
        cargo = Bytes.toUint64(intMap)
        self.intMap = intMap
        alerts = CGMAlert.fromBitmask(intMap)
    }

    /// CGM alert bit positions.
    public enum CGMAlert: Int, CaseIterable, Comparable, NotificationEnum {
        /// Tandem firmware name: Alert_CGM_DEPRECATED_3
        case DEFAULT_CGM_ALERT_0 = 0
        /// Tandem firmware name: Alert_CGM_FIXED_LOW
        case FIXED_LOW_CGM_ALERT = 1
        /// Tandem firmware name: Alert_CGM_USER_HIGH_EGV
        case HIGH_CGM_ALERT = 2
        /// Tandem firmware name: Alert_CGM_USER_LOW_EGV
        case LOW_CGM_ALERT = 3
        /// Tandem firmware name: Alert_CGM_CALIBRATION_REQUEST
        case CALIBRATION_REQUEST_CGM_ALERT = 4
        /// Tandem firmware name: Alert_CGM_RISE
        case RISE_CGM_ALERT = 5
        /// Tandem firmware name: Alert_CGM_RAPID_RISE
        case RAPID_RISE_CGM_ALERT = 6
        /// Tandem firmware name: Alert_CGM_FALL
        case FALL_CGM_ALERT = 7
        /// Tandem firmware name: Alert_CGM_RAPID_FALL
        case RAPID_FALL_CGM_ALERT = 8
        /// Tandem firmware name: Alert_CGM_CALIB_ERROR
        case LOW_CALIBRATION_ERROR_CGM_ALERT = 9
        /// Tandem firmware name: Alert_CGM_CALIB_HIGH_WEDGE
        case HIGH_CALIBRATION_ERROR_CGM_ALERT = 10
        /// Tandem firmware name: Alert_CGM_SENSOR_FAILED
        case SENSOR_FAILED_CGM_ALERT = 11
        /// Tandem firmware name: Alert_CGM_SENSOR_EXPIRING
        case SENSOR_EXPIRING_CGM_ALERT = 12
        /// Tandem firmware name: Alert_CGM_SENSOR_EXPIRED
        case SENSOR_EXPIRED_CGM_ALERT = 13
        /// Tandem firmware name: Alert_CGM_OUT_OF_RANGE
        case OUT_OF_RANGE_CGM_ALERT = 14
        /// Tandem firmware name: Alert_CGM_DEPRECATED
        case DEFAULT_CGM_ALERT_15 = 15
        /// Tandem firmware name: Alert_CGM_CALIB_START_FIRST
        case FIRST_START_CALIBRATION_CGM_ALERT = 16
        /// Tandem firmware name: Alert_CGM_CALIB_START_SECOND
        case SECOND_START_CALIBRATION_CGM_ALERT = 17
        /// Tandem firmware name: Alert_CGM_CALIB_REQUIRED
        case CALIBRATION_REQUIRED_CGM_ALERT = 18
        /// Tandem firmware name: Alert_CGM_LOW_TX_BATTERY
        case LOW_TRANSMITTER_CGM_ALERT = 19
        /// Tandem firmware name: Alert_CGM_TRANSMITTER_ERROR
        case TRANSMITTER_CGM_ALERT = 20
        /// Tandem firmware name: Alert_CGM_DEPRECATED_2
        case DEFAULT_CGM_ALERT_21 = 21
        /// Tandem firmware name: Alert_CGM_SENSOR_EXPIRING_SOON
        case SENSOR_EXPIRING_CGM_ALERT2 = 22
        /// Tandem firmware name: Alert_CGM_DEPRECATED_4
        case DEFAULT_CGM_ALERT_23 = 23
        /// Tandem firmware name: Alert_CGM_URGENT_LOW_SOON
        case URGENT_LOW_SOON_CGM_ALERT = 24
        /// Tandem firmware name: Alert_CGM_SENSOR_REUSE
        case SENSOR_REUSE = 25
        /// Tandem firmware name: Alert_CGM_SENSOR_TEMP
        case TEMPERATURE_CGM_ALERT = 26
        /// Tandem firmware name: Alert_CGM_CONNECTION_ERROR
        case FAILED_CONNECTION_CGM_ALERT = 27
        /// Tandem firmware name: Alert_CGM_CHECK_SENSOR
        case CHECK_SENSOR_CGM_ALERT = 28
        /// Tandem firmware name: Alert_CGM_EGV_UNUSABLE
        case EGV_UNUSABLE_CGM_ALERT = 29
        /// Tandem firmware name: Alert_CGM_UNUSED1
        case DEFAULT_CGM_ALERT_30 = 30
        /// Tandem firmware name: Alert_CGM_GRACE_PERIOD_START
        case GRACE_PERIOD_START_CGM_ALERT = 31
        /// Tandem firmware name: Alert_CGM_GRACE_PERIOD_EXPIRING_SOON
        case GRACE_PERIOD_EXPIRING_SOON_CGM_ALERT = 32
        /// Tandem firmware name: NUM_CGM_ALERTS
        case DEFAULT_CGM_ALERT_33 = 33
        case DEFAULT_CGM_ALERT_34 = 34
        case DEFAULT_CGM_ALERT_35 = 35
        case DEFAULT_CGM_ALERT_36 = 36
        case DEFAULT_CGM_ALERT_37 = 37
        case DEFAULT_CGM_ALERT_38 = 38
        case TRANSMITTER_EXPIRED_CGM_ALERT = 39
        case PUMP_BLUETOOTH_ERROR_CGM_ALERT = 40
        case DEFAULT_CGM_ALERT_41 = 41
        case DEFAULT_CGM_ALERT_42 = 42
        case DEFAULT_CGM_ALERT_43 = 43
        case DEFAULT_CGM_ALERT_44 = 44
        /// Name derived from tconnectsync's cloud-export dictionaries (CGM_ALERTS_DICT["45"] == "CGM Transmitter Expiring Soon").
        case TRANSMITTER_EXPIRING_CGM_ALERT = 45
        /// Name derived from tconnectsync's cloud-export dictionaries (CGM_ALERTS_DICT["46"] == "CGM Transmitter Expiring 2").
        case TRANSMITTER_EXPIRING_CGM_ALERT2 = 46
        case DEFAULT_CGM_ALERT_47 = 47
        /// Name derived from tconnectsync's cloud-export dictionaries (CGM_ALERTS_DICT["48"] == "CGM Unavailable").
        case UNAVAILABLE_CGM_ALERT = 48
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
            lhs.rawValue < rhs.rawValue
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

        public var id: Int { rawValue }

        public var notificationDescription: String? {
            let rawName = String(describing: self)
            return rawName.hasPrefix("DEFAULT_CGM_ALERT") ? nil : rawName
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
        "CGMAlertStatusResponse(cargo=\(cargo.hexadecimalString), alerts=\(alerts), intMap=\(intMap))"
    }
}
