import Foundation

/// Container for managing notification-related responses from the pump.
/// Aggregates seven different status response types and tracks when each was last updated.
public class NotificationBundle {
    private let log = TandemLogger(category: "NotificationBundle")

    public var alertStatusResponse: AlertStatusResponse?
    public var reminderStatusResponse: ReminderStatusResponse?
    public var alarmStatusResponse: AlarmStatusResponse?
    public var cgmAlertStatusResponse: CGMAlertStatusResponse?
    public var malfunctionStatusResponse: MalfunctionStatusResponse?
    public var otherNotificationStatusResponse: OtherNotificationStatusResponse?
    public var otherNotification2StatusResponse: OtherNotification2StatusResponse?

    private var lastUpdatedTimes: [String: Date] = [:]
    private let lock = NSLock()

    public init() {}

    /// Returns a list of request message types needed to populate the bundle.
    public static func allRequests() -> [Message] {
        [
            AlertStatusRequest(),
            ReminderStatusRequest(),
            AlarmStatusRequest(),
            CGMAlertStatusRequest(),
            MalfunctionStatusRequest(),
            OtherNotificationStatusRequest(),
            OtherNotification2StatusRequest()
        ]
    }

    /// Returns the corresponding response class types for the bundle's status categories.
    public static func responseClasses() -> [Message.Type] {
        [
            AlertStatusResponse.self,
            ReminderStatusResponse.self,
            AlarmStatusResponse.self,
            CGMAlertStatusResponse.self,
            MalfunctionStatusResponse.self,
            OtherNotificationStatusResponse.self,
            OtherNotification2StatusResponse.self
        ]
    }

    /// Validates whether a given message is one of the recognized notification response types.
    public static func isNotificationResponse(_ message: Message) -> Bool {
        message is AlertStatusResponse ||
            message is ReminderStatusResponse ||
            message is AlarmStatusResponse ||
            message is CGMAlertStatusResponse ||
            message is MalfunctionStatusResponse ||
            message is OtherNotificationStatusResponse ||
            message is OtherNotification2StatusResponse
    }

    /// Accepts a notification response, stores it in the appropriate field, and records the current timestamp.
    public func add(_ message: Message) {
        let timestamp = Date()
        let typeName = String(describing: type(of: message))

        lock.lock()
        defer { lock.unlock() }

        if let response = message as? AlertStatusResponse {
            alertStatusResponse = response
            lastUpdatedTimes[typeName] = timestamp
        } else if let response = message as? ReminderStatusResponse {
            reminderStatusResponse = response
            lastUpdatedTimes[typeName] = timestamp
        } else if let response = message as? AlarmStatusResponse {
            alarmStatusResponse = response
            lastUpdatedTimes[typeName] = timestamp
        } else if let response = message as? CGMAlertStatusResponse {
            cgmAlertStatusResponse = response
            lastUpdatedTimes[typeName] = timestamp
        } else if let response = message as? MalfunctionStatusResponse {
            malfunctionStatusResponse = response
            lastUpdatedTimes[typeName] = timestamp
        } else if let response = message as? OtherNotificationStatusResponse {
            otherNotificationStatusResponse = response
            lastUpdatedTimes[typeName] = timestamp
        } else if let response = message as? OtherNotification2StatusResponse {
            otherNotification2StatusResponse = response
            lastUpdatedTimes[typeName] = timestamp
        }
    }

    /// Assembles all active notifications into a single sorted list.
    public func get() -> [NotificationItem] {
        lock.lock()
        defer { lock.unlock() }

        var items: [NotificationItem] = []
        let notificationMessages: [NotificationMessage] = [
            alertStatusResponse as NotificationMessage?,
            alarmStatusResponse as NotificationMessage?,
            reminderStatusResponse as NotificationMessage?,
            cgmAlertStatusResponse as NotificationMessage?
        ].compactMap { $0 }

        // Add alerts
        if let response = alertStatusResponse {
            for alert in response.alerts.sorted() {
                items.append(NotificationItem(
                    type: .alert,
                    id: UInt32(alert.rawValue),
                    name: String(describing: alert),
                    notificationDescription: alert.notificationDescription
                ))
            }
        }

        // Add alarms
        if let response = alarmStatusResponse {
            for alarm in response.alarms.sorted() {
                items.append(NotificationItem(
                    type: .alarm,
                    id: UInt32(alarm.rawValue),
                    name: String(describing: alarm),
                    notificationDescription: alarm.notificationDescription
                ))
            }
        }

        // Add reminders
        if let response = reminderStatusResponse {
            for reminder in response.reminders.sorted(by: { $0.rawValue < $1.rawValue }) {
                items.append(NotificationItem(
                    type: .reminder,
                    id: UInt32(reminder.rawValue),
                    name: String(describing: reminder),
                    notificationDescription: reminder.notificationDescription
                ))
            }
        }

        // Add CGM alerts
        if let response = cgmAlertStatusResponse {
            for alert in response.alerts.sorted(by: { $0.rawValue < $1.rawValue }) {
                items.append(NotificationItem(
                    type: .cgmAlert,
                    id: UInt32(alert.rawValue),
                    name: String(describing: alert),
                    notificationDescription: alert.notificationDescription
                ))
            }
        }

        // Add malfunction if present
        if let response = malfunctionStatusResponse, response.hasMalfunction(notificationMessages) {
            items.append(NotificationItem(
                type: .malfunction,
                id: UInt32(response.codeA),
                name: response.errorString,
                notificationDescription: response.notificationDescription
            ))
        }

        return items
    }

    /// Calculates the total number of active notifications across all response types.
    /// This count is derived directly from `get()` to ensure consistency between
    /// the displayed count and the actual items list.
    public func getNotificationCount() -> Int {
        get().count
    }

    /// Boolean check for whether any notifications exist.
    public var isEmpty: Bool {
        getNotificationCount() == 0
    }

    /// Returns the last updated time for a specific response type.
    public func lastUpdatedTime(for type: Message.Type) -> Date? {
        lock.lock()
        defer { lock.unlock() }

        let typeName = String(describing: type)
        return lastUpdatedTimes[typeName]
    }
}

/// Represents a single notification item.
public struct NotificationItem: Identifiable, Hashable {
    public let id: UUID
    public let type: NotificationType
    public let notificationId: UInt32
    public let name: String
    public let notificationDescription: String?

    public init(type: NotificationType, id notificationId: UInt32, name: String, notificationDescription: String? = nil) {
        self.id = UUID()
        self.type = type
        self.notificationId = notificationId
        self.name = name
        self.notificationDescription = notificationDescription
    }

    public enum NotificationType {
        case alert
        case reminder
        case alarm
        case cgmAlert
        case malfunction

        public var title: String {
            switch self {
            case .alert: return "Alert"
            case .reminder: return "Reminder"
            case .alarm: return "Alarm"
            case .cgmAlert: return "CGM Alert"
            case .malfunction: return "Malfunction"
            }
        }

        public var dismissType: DismissNotificationRequest.NotificationType? {
            switch self {
            case .alert: return .alert
            case .reminder: return .reminder
            case .alarm: return .alarm
            case .cgmAlert: return .cgmAlert
            case .malfunction: return nil // Malfunctions cannot be dismissed
            }
        }
    }

    /// Format the notification name for display.
    public var title: String {
        // Convert enum case names to readable format
        // e.g., "LOW_INSULIN_ALERT" -> "Low Insulin Alert"
        name
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Whether this notification can be dismissed.
    public var canDismiss: Bool {
        type.dismissType != nil
    }
}

public extension NotificationBundle {
    var description: String {
        let count = getNotificationCount()
        return "NotificationBundle(count=\(count), bundle=\(get().debugDescription))"
    }
}
