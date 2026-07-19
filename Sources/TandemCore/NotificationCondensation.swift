import Foundation

/// A set of pump notifications that fire together and that the pump acknowledges
/// together: dismissing any single member causes the pump to clear every member.
///
/// Because the members represent one underlying condition, they are condensed into
/// a single row in the UI (e.g. "Alarm: RESUME_PUMP_ALARM, RESUME_PUMP_ALARM2") and
/// dismissed with a single request targeting the representative member — the pump
/// then clears the remaining members on its own.
///
/// The "acknowledged together" property is the defining invariant: a set is only
/// modelled as a condensation group when dismissing its representative is known to
/// clear the whole set on the pump. Groups are declared per notification category
/// on that category's own enum (see
/// `AlarmStatusResponse.AlarmResponseType.condensationGroups`) and aggregated into
/// the category-agnostic catalog in `NotificationCondensation`.
public struct NotificationCondensationGroup: Equatable {
    /// The category every member belongs to. Condensation never spans categories,
    /// because the pump's acknowledge-together behaviour is scoped to a single
    /// status surface.
    public let type: NotificationItem.NotificationType

    /// Member notification ids in display order. `members.first` is the
    /// representative dismissed on the user's behalf.
    public let members: [UInt32]

    public init(type: NotificationItem.NotificationType, members: [UInt32]) {
        precondition(members.count >= 2, "A condensation group must declare at least two members")
        self.type = type
        self.members = members
    }

    /// The id dismissed on the user's behalf; the pump acknowledges the remaining
    /// members automatically.
    public var representative: UInt32 { members[0] }

    /// Whether the given item is a member of this group.
    func contains(_ item: NotificationItem) -> Bool {
        item.type == type && members.contains(item.notificationId)
    }
}

/// Catalog of every condensation group plus the logic that collapses a flat list of
/// `NotificationItem`s down to one row per co-firing group.
///
/// This lives in `TandemCore` (not the UI) deliberately: condensation changes both
/// what the user sees *and* the dismissal/count semantics, so every consumer of
/// `NotificationBundle.get()` — the settings UI, the badge count, the CLI — observes
/// the same collapsed view.
public enum NotificationCondensation {
    /// All condensation groups, contributed by each notification category.
    ///
    /// To add a new group, declare it on the relevant category enum (mirroring
    /// `AlarmStatusResponse.AlarmResponseType.condensationGroups`) and map it in
    /// here. Nothing else in the pipeline needs to change.
    public static let groups: [NotificationCondensationGroup] =
        AlarmStatusResponse.AlarmResponseType.condensationGroups.map { members in
            NotificationCondensationGroup(
                type: .alarm,
                members: members.map { UInt32($0.rawValue) }
            )
        }

    /// Collapses each configured group of co-firing notifications into a single
    /// representative row.
    ///
    /// A group condenses only when two or more of its members are actually present;
    /// a lone member renders normally (and, on the next refresh after a partial
    /// pump acknowledge, so does any straggler). The collapsed row keeps the
    /// position of the group's first present member, so overall ordering is stable.
    public static func condense(_ items: [NotificationItem]) -> [NotificationItem] {
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

            result.append(condensed(from: present))
            for member in present {
                consumed.insert(member.id)
            }
        }

        return result
    }

    /// Returns the group's present members in the group's declared order, skipping
    /// any item already consumed by an earlier group.
    private static func orderedMembers(
        of group: NotificationCondensationGroup,
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

    /// Builds the single row that represents a condensed group. The first present
    /// member is the representative — its id drives dismissal and its description is
    /// shown — and the remaining member names are appended to the category line.
    private static func condensed(from members: [NotificationItem]) -> NotificationItem {
        let representative = members[0]
        return NotificationItem(
            type: representative.type,
            id: representative.notificationId,
            name: representative.name,
            notificationDescription: representative.notificationDescription,
            groupedNames: members.dropFirst().map(\.name)
        )
    }
}
