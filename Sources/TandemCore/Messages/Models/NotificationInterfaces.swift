import Foundation

/// Marker for notification enum values that can expose an identifier and optional description.
public protocol NotificationEnum {
    var id: Int { get }
    var notificationDescription: String? { get }
}

public extension NotificationEnum {
    var notificationDescription: String? { nil }
}

/// Common surface for notification-carrying messages.
public protocol NotificationMessage: Message {
    /// Number of notifications represented by the message payload.
    var notificationCount: Int { get }

    /// Notification identifiers present in the payload.
    var notificationIds: Set<Int> { get }
}

public extension NotificationMessage {
    var notificationCount: Int { 0 }
    var notificationIds: Set<Int> { [] }

    /// Convenience for checking whether the message reports any notifications.
    var isEmpty: Bool { notificationCount == 0 }
}
