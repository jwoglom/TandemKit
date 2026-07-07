import Foundation

/// Container for managing notification-related responses from the pump.
/// Aggregates seven different status response types and tracks when each was last updated.
public class NotificationBundle {
    private let log = TandemLogger(category: "NotificationBundle")

    public var alertStatusResponse: AlertStatusResponse?
    public var reminderStatusResponse: ReminderStatusResponse?
    public var alarmStatusResponse: AlarmStatusResponse?
    public var cgmAlertStatusResponse: CGMAlertStatusResponse?
    public var highestAamResponse: HighestAamResponse?
    public var otherNotificationStatusResponse: OtherNotificationStatusResponse?
    public var otherNotification2StatusResponse: OtherNotification2StatusResponse?

    /// Corroborating malfunction data used to confirm that a `HighestAamResponse` is a
    /// genuine malfunction rather than an alert/alarm. Mirrors PumpX2's `NotificationBundle`.
    public var malfunctionBitmaskStatusResponse: MalfunctionBitmaskStatusResponse?
    public var activeAamBitsResponses: [ActiveAamBitsResponse.AamType: ActiveAamBitsResponse] = [:]

    private var lastUpdatedTimes: [String: Date] = [:]
    private let lock = NSLock()

    public init() {}

    /// Returns a list of request message types needed to populate the bundle.
    ///
    /// Mirrors PumpX2's `NotificationBundle.allRequests`: in addition to the alert/alarm/CGM
    /// surfaces, this requests `MalfunctionStatusRequest`, `HighestAamRequest`, and the
    /// active-AAM-bits for alarm (type 2) and malfunction (type 4). The latter two corroborate
    /// whether a `HighestAamResponse` is a genuine malfunction (see `get()`).
    ///
    /// When `apiVersion` is provided, requests whose `minApi` exceeds it are filtered out
    /// (e.g. `ActiveAamBitsRequest` requires Mobi API v3.5).
    public static func allRequests(apiVersion: ApiVersion? = nil) -> [Message] {
        let requests: [Message] = [
            AlertStatusRequest(),
            AlarmStatusRequest(),
            CGMAlertStatusRequest(),
            MalfunctionStatusRequest(),
            HighestAamRequest(),
            ActiveAamBitsRequest(aamType: 2),
            ActiveAamBitsRequest(aamType: 4)
        ]

        guard let apiVersion = apiVersion else {
            return requests
        }

        return requests.filter { supportsApiVersion($0, apiVersion) }
    }

    /// Whether the pump's negotiated API version is new enough to support the given request.
    private static func supportsApiVersion(_ request: Message, _ apiVersion: ApiVersion) -> Bool {
        let minApi = type(of: request).props.minApi.value
        return !minApi.greaterThan(apiVersion)
    }

    /// Returns the corresponding response class types for the bundle's status categories.
    public static func responseClasses() -> [Message.Type] {
        [
            AlertStatusResponse.self,
            ReminderStatusResponse.self,
            AlarmStatusResponse.self,
            CGMAlertStatusResponse.self,
            HighestAamResponse.self,
            OtherNotificationStatusResponse.self,
            OtherNotification2StatusResponse.self,
            MalfunctionBitmaskStatusResponse.self,
            ActiveAamBitsResponse.self
        ]
    }

    /// Validates whether a given message is one of the recognized notification response types.
    public static func isNotificationResponse(_ message: Message) -> Bool {
        message is AlertStatusResponse ||
            message is ReminderStatusResponse ||
            message is AlarmStatusResponse ||
            message is CGMAlertStatusResponse ||
            message is HighestAamResponse ||
            message is OtherNotificationStatusResponse ||
            message is OtherNotification2StatusResponse ||
            message is MalfunctionBitmaskStatusResponse ||
            message is ActiveAamBitsResponse
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
        } else if let response = message as? HighestAamResponse {
            highestAamResponse = response
            lastUpdatedTimes[typeName] = timestamp
        } else if let response = message as? OtherNotificationStatusResponse {
            otherNotificationStatusResponse = response
            lastUpdatedTimes[typeName] = timestamp
        } else if let response = message as? OtherNotification2StatusResponse {
            otherNotification2StatusResponse = response
            lastUpdatedTimes[typeName] = timestamp
        } else if let response = message as? MalfunctionBitmaskStatusResponse {
            malfunctionBitmaskStatusResponse = response
            lastUpdatedTimes[typeName] = timestamp
        } else if let response = message as? ActiveAamBitsResponse {
            activeAamBitsResponses[response.aamType] = response
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

        // Add malfunction if present.
        //
        // Mirrors PumpX2's `NotificationBundle.get()`: a malfunction is only surfaced when all
        // three gates pass, otherwise an ordinary alert/alarm carried by `HighestAamResponse`
        // would appear as a spurious malfunction:
        //   1. `hasMalfunction` — not an ignorable code and not a known concurrent notification.
        //   2. `matchesActiveMalfunction` — corroborated by the active AAM-bits (malfunction
        //      type) or the malfunction bitmask, when that data is available.
        //   3. a non-blank error string.
        if let response = highestAamResponse {
            let activeMalfunctionBits = activeAamBitsResponses[.malfunction]
            if response.hasMalfunction(notificationMessages),
               response.matchesActiveMalfunction(
                   activeMalfunctionBits: activeMalfunctionBits,
                   malfunctionBitmaskStatusResponse: malfunctionBitmaskStatusResponse
               ),
               !response.errorString.isEmpty
            {
                items.append(NotificationItem(
                    type: .malfunction,
                    id: UInt32(response.aamId),
                    name: response.errorString,
                    notificationDescription: response.notificationDescription
                ))
            }
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

    /// Text shown to the user. Prefers the pump's notification description
    /// (alerts / alarms / malfunctions) and falls back to the prettified enum
    /// name when no distinct description exists — e.g. CGM alerts and reminders,
    /// which pumpX2 also leaves name-only.
    public var displayTitle: String {
        if let description = notificationDescription,
           !description.isEmpty,
           description != name {
            return description
        }
        return title
    }

    /// Whether this notification can be dismissed.
    public var canDismiss: Bool {
        type.dismissType != nil
    }

    /// The notification's category paired with its underlying enum name,
    /// e.g. "Alarm: OCCLUSION_ALARM" or "Alert: LOW_INSULIN_ALERT".
    public var categoryTitle: String {
        "\(type.title): \(name)"
    }
}

public extension NotificationBundle {
    var description: String {
        let count = getNotificationCount()
        return "NotificationBundle(count=\(count), bundle=\(get().debugDescription))"
    }
}
