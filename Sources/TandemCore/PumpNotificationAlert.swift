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

public extension NotificationItem {
    var severity: PumpNotificationSeverity {
        type.severity
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
