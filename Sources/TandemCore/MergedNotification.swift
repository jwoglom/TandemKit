import Foundation

/// A set of pump notifications that fire together and that the pump acknowledges
/// together: dismissing any single member causes the pump to clear every member.
///
/// Because the members represent one underlying condition, they are merged into a
/// single row in the UI (e.g. "Alarm: RESUME_PUMP_ALARM, RESUME_PUMP_ALARM2") and
/// dismissed with a single request targeting the `primary` member — the pump then
/// clears the remaining members on its own.
///
/// The "acknowledged together" property is the defining invariant: a set is only
/// modelled as a merged group when dismissing its primary is known to clear the
/// whole set on the pump. Groups are declared per notification category on that
/// category's own enum (see `AlarmStatusResponse.AlarmResponseType.mergedGroups`)
/// and aggregated into the category-agnostic catalog in `MergedNotification`.
public struct MergedNotificationGroup: Equatable {
    /// The category every member belongs to. Merging never spans categories,
    /// because the pump's acknowledge-together behaviour is scoped to a single
    /// status surface.
    public let type: NotificationItem.NotificationType

    /// Member notification ids in display order.
    public let members: [UInt32]

    /// The member whose description is shown and whose id is dismissed (the pump
    /// acknowledges the remaining members automatically). It is listed first in the
    /// merged row. Defaults to the first member.
    public let primary: UInt32

    public init(type: NotificationItem.NotificationType, members: [UInt32], primary: UInt32? = nil) {
        precondition(members.count >= 2, "A merged group must declare at least two members")
        let resolvedPrimary = primary ?? members[0]
        precondition(members.contains(resolvedPrimary), "primary must be one of the members")
        self.type = type
        self.members = members
        self.primary = resolvedPrimary
    }

    /// Whether the given item is a member of this group.
    func contains(_ item: NotificationItem) -> Bool {
        item.type == type && members.contains(item.notificationId)
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
    /// All merged-notification groups, contributed by each notification category.
    ///
    /// To add a new group, declare it on the relevant category enum (mirroring
    /// `AlarmStatusResponse.AlarmResponseType.mergedGroups`) and map it in here.
    /// Nothing else in the pipeline needs to change.
    public static let groups: [MergedNotificationGroup] =
        AlarmStatusResponse.AlarmResponseType.mergedGroups.map { group in
            MergedNotificationGroup(
                type: .alarm,
                members: group.members.map { UInt32($0.rawValue) },
                primary: UInt32(group.primary.rawValue)
            )
        }

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
        group.members.compactMap { memberId in
            items.first {
                $0.type == group.type
                    && $0.notificationId == memberId
                    && !consumed.contains($0.id)
            }
        }
    }

    /// Builds the single row that represents a merged group. The `primary` member —
    /// its id drives dismissal and its description is shown — is listed first, and
    /// the remaining members follow in their declared order.
    private static func merged(from members: [NotificationItem], primary: UInt32) -> NotificationItem {
        let primaryItem = members.first { $0.notificationId == primary } ?? members[0]
        let others = members.filter { $0.id != primaryItem.id }
        return NotificationItem(
            type: primaryItem.type,
            id: primaryItem.notificationId,
            name: primaryItem.name,
            notificationDescription: primaryItem.notificationDescription,
            mergedNames: others.map(\.name)
        )
    }
}
