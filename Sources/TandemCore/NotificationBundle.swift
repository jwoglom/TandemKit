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
    public static func allRequests(apiVersion: ApiVersion? = nil) -> [any PumpRequest] {
        let requests: [any PumpRequest] = [
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

        // Merge any sets of co-firing notifications (that the pump acknowledges
        // together) into a single row. Applied here so every consumer — the UI, the
        // badge count via `getNotificationCount()`, and the CLI — sees one
        // consistent, merged view.
        return MergedNotification.merge(items)
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

    /// Whether the notification identified by `(type, id)` is currently active in
    /// the bundle's raw per-category state.
    ///
    /// Reads the underlying status responses directly (not `get()`), so it reports
    /// a member's presence independently of whether it is being merged into a row.
    /// Used after a dismissal reload to decide which merged members the pump has not
    /// already cleared on its own.
    public func isActive(type: NotificationItem.NotificationType, id: UInt32) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        switch type {
        case .alert:
            return alertStatusResponse?.alerts.contains { UInt32($0.rawValue) == id } ?? false
        case .alarm:
            return alarmStatusResponse?.alarms.contains { UInt32($0.rawValue) == id } ?? false
        case .reminder:
            return reminderStatusResponse?.reminders.contains { UInt32($0.rawValue) == id } ?? false
        case .cgmAlert:
            return cgmAlertStatusResponse?.alerts.contains { UInt32($0.rawValue) == id } ?? false
        case .malfunction:
            // Malfunctions are not dismissable and never participate in merged groups.
            return false
        }
    }

    /// The alarms the pump raises purely to tell the user that insulin is not being
    /// delivered, in acknowledgement order. The pump encodes the one condition under two
    /// ids, which is why they also form a merged row (see `MergedNotification.groups`).
    public static let resumePumpAlarms: [AlarmStatusResponse.AlarmResponseType] = [
        .RESUME_PUMP_ALARM,
        .RESUME_PUMP_ALARM2
    ]

    /// Which of the `resumePumpAlarms` are currently active, in acknowledgement order.
    ///
    /// Reads the raw alarm state (via `isActive(type:id:)`), so a lone alarm is reported
    /// just the same as the pair that renders as a single merged row.
    public func activeResumePumpAlarms() -> [AlarmStatusResponse.AlarmResponseType] {
        NotificationBundle.resumePumpAlarms.filter { isActive(type: .alarm, id: UInt32($0.rawValue)) }
    }

    /// Returns the last updated time for a specific response type.
    public func lastUpdatedTime(for type: Message.Type) -> Date? {
        lock.lock()
        defer { lock.unlock() }

        let typeName = String(describing: type)
        return lastUpdatedTimes[typeName]
    }

    /// Notification categories whose status response actually arrived in this bundle.
    ///
    /// The bundle is rebuilt on every fetch pass, so a `nil` response field means the
    /// corresponding status request failed (or was never sent) during that pass — the pump's
    /// state for that category is unknown, not empty. Consumers reconciling externally-issued
    /// notifications (e.g. LoopKit alerts) must only treat a category's notifications as
    /// cleared when the category appears here; otherwise a single dropped BLE round trip
    /// would retract alerts that are still active on the pump.
    ///
    /// Malfunctions key off `HighestAamResponse` alone: the corroborating
    /// `MalfunctionBitmaskStatusResponse`/`ActiveAamBitsResponse` may legitimately be absent
    /// (filtered by `minApi`), and `get()` already treats missing corroboration as best-effort.
    public var fetchedCategories: Set<NotificationItem.NotificationType> {
        lock.lock()
        defer { lock.unlock() }

        var categories: Set<NotificationItem.NotificationType> = []
        if alertStatusResponse != nil { categories.insert(.alert) }
        if alarmStatusResponse != nil { categories.insert(.alarm) }
        if reminderStatusResponse != nil { categories.insert(.reminder) }
        if cgmAlertStatusResponse != nil { categories.insert(.cgmAlert) }
        if highestAamResponse != nil { categories.insert(.malfunction) }
        return categories
    }
}

/// Represents a single notification item.
public struct NotificationItem: Identifiable, Hashable {
    public let id: UUID
    public let type: NotificationType
    public let notificationId: UInt32
    public let name: String
    public let notificationDescription: String?

    /// The other notifications merged into this row, in display order. Empty for an
    /// ordinary (non-merged) notification. Each member carries its own category and
    /// id — a merged group may span categories (e.g. an alert + an alarm) — so
    /// dismissal can acknowledge every member individually. The row's own
    /// `type`/`notificationId` are the primary; see `MergedNotificationGroup`.
    public let mergedMembers: [MergedMember]

    /// A single non-primary notification folded into a merged row.
    public struct MergedMember: Hashable {
        public let type: NotificationType
        public let id: UInt32
        public let name: String

        public init(type: NotificationType, id: UInt32, name: String) {
            self.type = type
            self.id = id
            self.name = name
        }
    }

    public init(
        type: NotificationType,
        id notificationId: UInt32,
        name: String,
        notificationDescription: String? = nil,
        mergedMembers: [MergedMember] = []
    ) {
        self.id = UUID()
        self.type = type
        self.notificationId = notificationId
        self.name = name
        self.notificationDescription = notificationDescription
        self.mergedMembers = mergedMembers
    }

    /// Names of the other notifications merged into this row, in display order.
    public var mergedNames: [String] { mergedMembers.map(\.name) }

    public enum NotificationType: String, CaseIterable {
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

    /// The notification's category paired with its underlying enum name(s),
    /// e.g. "Alarm: OCCLUSION_ALARM" or "Alert: LOW_INSULIN_ALERT". When several
    /// co-firing notifications are merged into one row, every member name is listed
    /// in order, e.g. "Alarm: RESUME_PUMP_ALARM, RESUME_PUMP_ALARM2". A merged row
    /// that spans categories re-labels at each category boundary, e.g.
    /// "Alarm: RESUME_PUMP_ALARM, Alert: LOW_INSULIN_ALERT".
    public var categoryTitle: String {
        // Primary first, then the merged members in display order; a new
        // "Category:" prefix is emitted only when the category changes.
        var result = "\(type.title): \(name)"
        var previousType = type
        for member in mergedMembers {
            if member.type == previousType {
                result += ", \(member.name)"
            } else {
                result += ", \(member.type.title): \(member.name)"
                previousType = member.type
            }
        }
        return result
    }

    /// Identity that is stable across fetch passes, unlike `id` (a `UUID` minted per fetch).
    /// Used as the `LoopKit.Alert.AlertIdentifier` so the same pump notification maps to the
    /// same alert across polls and app restarts.
    ///
    /// Format: `<category>.<slug>.<id>` (e.g. `alarm.occlusion.2`, `alert.other.37`), where
    /// the slug is the human-readable condition name (`alertSlug`) that hosts key severity
    /// and display grouping on without hardcoding bit positions, and the trailing id is the
    /// bitmask bit position that keeps per-bit identity and routes acknowledgements back to
    /// `DismissNotificationRequest`. Malfunctions are `malfunction.<aamId>` — at most one is
    /// surfaced at a time and there is no condition enum to slug.
    public var stableIdentifier: String {
        if type == .malfunction {
            return "\(type.rawValue).\(notificationId)"
        }
        return "\(type.rawValue).\(alertSlug).\(notificationId)"
    }

    /// Inverse of `stableIdentifier`, used to route a LoopKit alert acknowledgement back to
    /// the pump notification it was issued for. The slug segment is not validated — routing
    /// only needs the category and id, so identifiers survive future slug-table refinements.
    /// Returns nil for identifiers this driver did not mint (including the pre-slug
    /// `<category>.<id>` format, which the reconciler then retracts and re-issues).
    public static func parseStableIdentifier(_ identifier: String) -> (type: NotificationType, notificationId: UInt32)? {
        let segments = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard let first = segments.first,
              let type = NotificationType(rawValue: String(first)),
              let last = segments.last,
              let notificationId = UInt32(last)
        else {
            return nil
        }

        switch (type, segments.count) {
        case (.malfunction, 2):
            return (type, notificationId)
        case (.malfunction, _):
            return nil
        case (_, 3) where !segments[1].isEmpty:
            return (type, notificationId)
        default:
            return nil
        }
    }
}

public extension NotificationBundle {
    var description: String {
        let count = getNotificationCount()
        return "NotificationBundle(count=\(count), bundle=\(get().debugDescription))"
    }
}
