import Foundation

/// Urgency classification for a pump notification, used to pick the delivery treatment when
/// forwarding notifications to an external alert system (e.g. LoopKit's `Alert`
/// interruption level). Deliberately LoopKit-free so the mapping is testable on platforms
/// without the binary framework.
public enum PumpNotificationSeverity {
    /// Informational only; may be delivered quietly.
    case informational
    /// The user should see this promptly (breaks through focus modes where permitted).
    case timeSensitive
    /// Insulin delivery is (or may be) stopped; must break through mute/Do Not Disturb
    /// where the hosting app holds the critical-alerts entitlement.
    case critical
}

public extension NotificationItem.NotificationType {
    /// How urgently a notification of this category must reach the user. Alarms and
    /// malfunctions accompany stopped or compromised insulin delivery; alerts and CGM alerts
    /// are actionable but not immediately dangerous; reminders are informational.
    var severity: PumpNotificationSeverity {
        switch self {
        case .alarm, .malfunction:
            return .critical
        case .alert, .cgmAlert:
            return .timeSensitive
        case .reminder:
            return .informational
        }
    }
}

// MARK: - Alert identifier slugs
//
// Human-readable middle segment of `NotificationItem.stableIdentifier`
// (`<category>.<slug>.<id>`). Hosts (e.g. Trio's alert catalog) key severity and display
// grouping on `<category>.<slug>` without hardcoding Tandem bit positions; the trailing id
// keeps per-bit identity and acknowledgement routing.
//
// These strings are ALERT IDENTITY and must stay stable: they are persisted in
// `issuedAlertIdentifiers`, recorded in LoopKit's alert store, and matched by host
// catalogs. They are deliberately explicit literals — never derived from enum case names —
// so renaming a case cannot silently change alert identity. Variants of the same
// user-facing condition (alternate bit positions across firmware) share one slug; unknown
// `DEFAULT_*` bits fall through to "other".

public extension AlertStatusResponse.AlertResponseType {
    var alertSlug: String {
        switch self {
        case .LOW_INSULIN_ALERT, .LOW_INSULIN_ALERT2: return "lowInsulin"
        case .USB_CONNECTION_ALERT: return "usbConnection"
        case .LOW_POWER_ALERT, .LOW_POWER_ALERT2: return "lowPower"
        case .DATA_ERROR_ALERT: return "dataError"
        case .AUTO_OFF_ALERT: return "autoOff"
        case .MAX_BASAL_RATE_ALERT: return "maxBasalRate"
        case .POWER_SOURCE_ALERT: return "powerSource"
        case .MIN_BASAL_ALERT, .MIN_BASAL_ALERT2: return "minBasal"
        case .CONNECTION_ERROR_ALERT, .CONNECTION_ERROR_ALERT2: return "connectionError"
        case .INCOMPLETE_BOLUS_ALERT: return "incompleteBolus"
        case .INCOMPLETE_TEMP_RATE_ALERT: return "incompleteTempRate"
        case .INCOMPLETE_CARTRIDGE_CHANGE_ALERT: return "incompleteCartridgeChange"
        case .INCOMPLETE_FILL_TUBING_ALERT: return "incompleteFillTubing"
        case .INCOMPLETE_FILL_CANNULA_ALERT: return "incompleteFillCannula"
        case .INCOMPLETE_SETTING_ALERT: return "incompleteSetting"
        case .MAX_BASAL_ALERT: return "maxBasal"
        case .LOW_TRANSMITTER_ALERT: return "lowTransmitter"
        case .TRANSMITTER_ALERT: return "transmitter"
        case .SENSOR_EXPIRING_ALERT: return "sensorExpiring"
        case .PUMP_REBOOTING_ALERT: return "pumpRebooting"
        case .DEVICE_CONNECTION_ERROR: return "deviceConnectionError"
        case .CGM_GRAPH_REMOVED: return "cgmGraphRemoved"
        case .INCOMPLETE_CALIBRATION: return "incompleteCalibration"
        case .CALIBRATION_TIMEOUT: return "calibrationTimeout"
        case .INVALID_TRANSMITTER_ID: return "invalidTransmitterId"
        case .BUTTON_ALERT: return "button"
        case .QUICK_BOLUS_ALERT: return "quickBolus"
        case .BASAL_IQ_ALERT: return "basalIQ"
        case .TRANSMITTER_END_OF_LIFE: return "transmitterEndOfLife"
        case .CGM_ERROR, .CGM_ERROR2, .CGM_ERROR3: return "cgmError"
        case .TRANSMITTER_EXPIRING_ALERT, .TRANSMITTER_EXPIRING_ALERT2, .TRANSMITTER_EXPIRING_ALERT3:
            return "transmitterExpiring"
        case .CGM_UNAVAILABLE: return "cgmUnavailable"
        case .FILL_TUBING_STILL_IN_PROGRESS: return "fillTubingInProgress"
        case .DEVICE_PAIRED: return "devicePaired"
        default: return "other"
        }
    }
}

public extension AlarmStatusResponse.AlarmResponseType {
    var alertSlug: String {
        switch self {
        case .CARTRIDGE_ALARM, .CARTRIDGE_ALARM_2, .CARTRIDGE_ALARM_3, .CARTRIDGE_ALARM_4,
             .CARTRIDGE_ALARM_5, .CARTRIDGE_ALARM_6, .CARTRIDGE_ALARM_7, .CARTRIDGE_ALARM_10,
             .CARTRIDGE_ALARM_11, .CARTRIDGE_ALARM_12, .CARTRIDGE_ALARM_34:
            return "cartridge"
        case .OCCLUSION_ALARM, .OCCLUSION_ALARM2: return "occlusion"
        case .PUMP_RESET_ALARM: return "pumpReset"
        case .AUTO_OFF_ALARM: return "autoOff"
        case .EMPTY_CARTRIDGE_ALARM: return "emptyCartridge"
        case .TEMPERATURE_ALARM, .TEMPERATURE_ALARM2, .TEMPERATURE_ALARM3: return "temperature"
        case .BATTERY_SHUTDOWN_ALARM: return "batteryShutdown"
        case .INVALID_DATE_ALARM: return "invalidDate"
        case .RESUME_PUMP_ALARM, .RESUME_PUMP_ALARM2: return "resumePump"
        case .ALTITUDE_ALARM: return "altitude"
        case .STUCK_BUTTON_ALARM: return "stuckButton"
        case .ATMOSPHERIC_PRESSURE_OUT_OF_RANGE_ALARM: return "atmosphericPressure"
        case .CARTRIDGE_REMOVED_ALARM: return "cartridgeRemoved"
        default: return "other"
        }
    }
}

public extension CGMAlertStatusResponse.CGMAlert {
    var alertSlug: String {
        switch self {
        case .FIXED_LOW_CGM_ALERT: return "fixedLow"
        case .HIGH_CGM_ALERT: return "high"
        case .LOW_CGM_ALERT: return "low"
        case .CALIBRATION_REQUEST_CGM_ALERT: return "calibrationRequest"
        case .RISE_CGM_ALERT: return "rise"
        case .RAPID_RISE_CGM_ALERT: return "rapidRise"
        case .FALL_CGM_ALERT: return "fall"
        case .RAPID_FALL_CGM_ALERT: return "rapidFall"
        case .LOW_CALIBRATION_ERROR_CGM_ALERT: return "lowCalibrationError"
        case .HIGH_CALIBRATION_ERROR_CGM_ALERT: return "highCalibrationError"
        case .SENSOR_FAILED_CGM_ALERT: return "sensorFailed"
        case .SENSOR_EXPIRING_CGM_ALERT, .SENSOR_EXPIRING_CGM_ALERT2: return "sensorExpiring"
        case .SENSOR_EXPIRED_CGM_ALERT: return "sensorExpired"
        case .OUT_OF_RANGE_CGM_ALERT: return "outOfRange"
        case .FIRST_START_CALIBRATION_CGM_ALERT: return "firstStartCalibration"
        case .SECOND_START_CALIBRATION_CGM_ALERT: return "secondStartCalibration"
        case .CALIBRATION_REQUIRED_CGM_ALERT: return "calibrationRequired"
        case .LOW_TRANSMITTER_CGM_ALERT: return "lowTransmitter"
        case .TRANSMITTER_CGM_ALERT: return "transmitter"
        case .SENSOR_REUSE: return "sensorReuse"
        case .TEMPERATURE_CGM_ALERT: return "temperature"
        case .FAILED_CONNECTION_CGM_ALERT: return "failedConnection"
        case .TRANSMITTER_EXPIRED_CGM_ALERT: return "transmitterExpired"
        case .PUMP_BLUETOOTH_ERROR_CGM_ALERT: return "pumpBluetoothError"
        default: return "other"
        }
    }
}

public extension NotificationItem {
    var severity: PumpNotificationSeverity {
        type.severity
    }

    /// Human-readable condition slug for this notification, resolved from the category's
    /// enum by bit position. Unknown bits (and reminders, which are never surfaced as
    /// LoopKit alerts) report "other". Malfunctions have no slug — their identifier is
    /// `malfunction.<aamId>`.
    var alertSlug: String {
        switch type {
        case .alert:
            return AlertStatusResponse.AlertResponseType(rawValue: Int(notificationId))?.alertSlug ?? "other"
        case .alarm:
            return AlarmStatusResponse.AlarmResponseType(rawValue: Int(notificationId))?.alertSlug ?? "other"
        case .cgmAlert:
            return CGMAlertStatusResponse.CGMAlert(rawValue: Int(notificationId))?.alertSlug ?? "other"
        case .reminder, .malfunction:
            return "other"
        }
    }

    /// Title for an externally-surfaced notification, e.g. "Pump Alarm".
    var alertTitle: String {
        switch type {
        case .cgmAlert:
            return type.title
        default:
            return "Pump \(type.title)"
        }
    }

    /// Body for an externally-surfaced notification. Prefers the pump-provided description;
    /// for malfunctions the `name` is the `HighestAamResponse.errorString` fault code
    /// (e.g. "12-0x2071"), which is appended so support can identify the fault.
    var alertBody: String {
        if type == .malfunction, displayTitle != name {
            return "\(displayTitle) (\(name))"
        }
        return displayTitle
    }

    /// Label for the acknowledge action. Dismissible notifications are cleared on the pump
    /// when acknowledged; malfunctions cannot be dismissed remotely, so acknowledging only
    /// silences the phone-side notification.
    var acknowledgeActionLabel: String {
        canDismiss ? "Dismiss" : "OK"
    }
}
