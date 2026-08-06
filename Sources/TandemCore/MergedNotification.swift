import Foundation

/// A set of pump notifications that fire together and are presented as one row.
///
/// Members may span categories (e.g. an alert *and* an alarm) — each carries its
/// own `(type, id)`. The row shows the `primary` member's description and lists it
/// first; dismissal acknowledges the primary, then reloads pump state and
/// acknowledges any member the pump did not clear on its own (see
/// `TandemPumpManager.dismissNotification`). Because dismissal verifies rather than
/// assumes, a group needs no guarantee that the pump co-acknowledges its members —
/// that only makes dismissal faster when it happens.
///
/// Groups are declared once in the central catalog `MergedNotification.groups`
/// using the type-safe member factories (`.alarm(_:)`, `.alert(_:)`, …).
public struct MergedNotificationGroup: Equatable {
    /// One member of a merged group, identified by its category and notification id.
    public struct Member: Hashable {
        public let type: NotificationItem.NotificationType
        public let id: UInt32

        public init(type: NotificationItem.NotificationType, id: UInt32) {
            self.type = type
            self.id = id
        }
    }

    /// Members in display order.
    public let members: [Member]

    /// The member whose description is shown and whose id is dismissed first (and is
    /// listed first in the merged row). Defaults to the first member.
    public let primary: Member

    public init(members: [Member], primary: Member? = nil) {
        precondition(members.count >= 2, "A merged group must declare at least two members")
        let resolvedPrimary = primary ?? members[0]
        precondition(members.contains(resolvedPrimary), "primary must be one of the members")
        self.members = members
        self.primary = resolvedPrimary
    }

    /// Whether the given item is a member of this group (matched by category + id).
    func contains(_ item: NotificationItem) -> Bool {
        members.contains { $0.type == item.type && $0.id == item.notificationId }
    }
}

/// Type-safe constructors that keep the catalog readable while pinning each member
/// to its category. Raw ids are never written by hand.
public extension MergedNotificationGroup.Member {
    static func alarm(_ value: AlarmStatusResponse.AlarmResponseType) -> Self {
        .init(type: .alarm, id: UInt32(value.rawValue))
    }

    static func alert(_ value: AlertStatusResponse.AlertResponseType) -> Self {
        .init(type: .alert, id: UInt32(value.rawValue))
    }

    static func reminder(_ value: ReminderStatusResponse.ReminderType) -> Self {
        .init(type: .reminder, id: UInt32(value.rawValue))
    }

    static func cgmAlert(_ value: CGMAlertStatusResponse.CGMAlert) -> Self {
        .init(type: .cgmAlert, id: UInt32(value.rawValue))
    }
}

/// Catalog of every merged-notification group plus the logic that collapses a flat
/// list of `NotificationItem`s down to one row per co-firing group.
///
/// This lives in `TandemCore` (not the UI) deliberately: merging changes both what
/// the user sees *and* the dismissal/count semantics, so every consumer of
/// `NotificationBundle.get()` — the settings UI, the badge count, the CLI — observes
/// the same merged view.
public enum MergedNotification {
    /// Every merged-notification group. Add entries here — same-category or
    /// cross-category — using the member factories.
    public static let groups: [MergedNotificationGroup] = [
        // Each pair below is one underlying condition the pump encodes under two
        // ids. Both members represent the same thing, so the default primary (the
        // first member) is fine.

        // Insulin delivery is off.
        MergedNotificationGroup(members: [.alarm(.RESUME_PUMP_ALARM), .alarm(.RESUME_PUMP_ALARM2)]),
        // Occlusion detected.
        MergedNotificationGroup(members: [.alarm(.OCCLUSION_ALARM), .alarm(.OCCLUSION_ALARM2)]),
        // Delivering at the minimum basal rate.
        MergedNotificationGroup(members: [.alert(.MIN_BASAL_ALERT), .alert(.MIN_BASAL_ALERT2)]),
        // Pump battery low.
        MergedNotificationGroup(members: [.alert(.LOW_POWER_ALERT), .alert(.LOW_POWER_ALERT2)]),
        // Low insulin remaining.
        MergedNotificationGroup(members: [.alert(.LOW_INSULIN_ALERT), .alert(.LOW_INSULIN_ALERT2)]),
        // Connection error.
        MergedNotificationGroup(members: [.alert(.CONNECTION_ERROR_ALERT), .alert(.CONNECTION_ERROR_ALERT2)])

        // Cross-category groups are supported too. Declare one when a real
        // co-acknowledged alert+alarm pair is identified, nominating whichever
        // member's description should represent the row, e.g.:
        // MergedNotificationGroup(
        //     members: [.alarm(.SOME_ALARM), .alert(.SOME_ALERT)],
        //     primary: .alert(.SOME_ALERT)
        // ),
    ]

    /// Merges each configured group of co-firing notifications into a single row.
    public static func merge(_ items: [NotificationItem]) -> [NotificationItem] {
        merge(items, using: groups)
    }

    /// Merges `items` against an explicit set of groups.
    ///
    /// A group merges only when two or more of its members are actually present; a
    /// lone member renders normally (and, on the next refresh after a partial pump
    /// acknowledge, so does any straggler). The merged row keeps the position of the
    /// group's first present member, so overall ordering is stable.
    ///
    /// Exposed (internally) so the merge can be exercised against ad-hoc groups in
    /// tests without touching the shared catalog.
    static func merge(_ items: [NotificationItem], using groups: [MergedNotificationGroup]) -> [NotificationItem] {
        guard !groups.isEmpty, items.count > 1 else { return items }

        var result: [NotificationItem] = []
        var consumed = Set<UUID>()

        for item in items where !consumed.contains(item.id) {
            guard let group = groups.first(where: { $0.contains(item) }) else {
                result.append(item)
                continue
            }

            let present = orderedMembers(of: group, in: items, excluding: consumed)
            guard present.count >= 2 else {
                // Only one member of the group is active; show it unchanged.
                result.append(item)
                continue
            }

            result.append(merged(from: present, primary: group.primary))
            for member in present {
                consumed.insert(member.id)
            }
        }

        return result
    }

    /// Returns the group's present members in the group's declared order, skipping
    /// any item already consumed by an earlier group.
    private static func orderedMembers(
        of group: MergedNotificationGroup,
        in items: [NotificationItem],
        excluding consumed: Set<UUID>
    ) -> [NotificationItem] {
        group.members.compactMap { member in
            items.first {
                $0.type == member.type
                    && $0.notificationId == member.id
                    && !consumed.contains($0.id)
            }
        }
    }

    /// Builds the single row that represents a merged group. The `primary` member —
    /// its id drives dismissal and its description is shown — is listed first, and
    /// the remaining members follow in their declared order.
    private static func merged(
        from members: [NotificationItem],
        primary: MergedNotificationGroup.Member
    ) -> NotificationItem {
        let primaryItem = members.first { $0.type == primary.type && $0.notificationId == primary.id }
            ?? members[0]
        let others = members
            .filter { $0.id != primaryItem.id }
            .map { NotificationItem.MergedMember(type: $0.type, id: $0.notificationId, name: $0.name) }
        return NotificationItem(
            type: primaryItem.type,
            id: primaryItem.notificationId,
            name: primaryItem.name,
            notificationDescription: primaryItem.notificationDescription,
            mergedMembers: others
        )
    }
}
