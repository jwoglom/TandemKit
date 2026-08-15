import Foundation

/// Result of diffing the pump's active notifications against the set of previously-issued
/// LoopKit alert identifiers.
struct TandemAlertReconciliation: Equatable {
    /// Pump notifications newly active since the last pass; issue a LoopKit alert for each.
    let itemsToIssue: [NotificationItem]
    /// Identifiers of previously-issued alerts whose pump notification is gone; retract each.
    let identifiersToRetract: [String]
    /// The issued-identifier set to persist after applying the issues/retractions above.
    let updatedIssuedIdentifiers: Set<String>

    var isEmpty: Bool {
        itemsToIssue.isEmpty && identifiersToRetract.isEmpty
    }
}

/// Pure diff between a freshly-fetched `NotificationBundle` and the persisted set of
/// already-issued alert identifiers. Deliberately free of LoopKit types and of any I/O so
/// the retraction rules are unit-testable in isolation.
enum TandemAlertReconciler {
    /// - Parameters:
    ///   - activeItems: pump notifications currently active, already filtered to the
    ///     categories the driver surfaces as LoopKit alerts (and with auto-acknowledged
    ///     basal alerts removed).
    ///   - fetchedCategories: categories whose status response actually arrived this fetch
    ///     pass (`NotificationBundle.fetchedCategories`). An issued alert is only retracted
    ///     when its category was fetched and no longer contains it — a failed status request
    ///     must never read as "cleared on the pump".
    ///   - issuedIdentifiers: persisted `NotificationItem.stableIdentifier`s of alerts
    ///     already issued to LoopKit.
    ///   - surfacedCategories: categories currently forwarded as LoopKit alerts. Issued
    ///     alerts whose category is no longer surfaced (e.g. CGM forwarding switched off)
    ///     are retracted regardless of fetch state.
    static func reconcile(
        activeItems: [NotificationItem],
        fetchedCategories: Set<NotificationItem.NotificationType>,
        issuedIdentifiers: Set<String>,
        surfacedCategories: Set<NotificationItem.NotificationType>
    ) -> TandemAlertReconciliation {
        let activeIdentifiers = Set(activeItems.map(\.stableIdentifier))

        var itemsToIssue: [NotificationItem] = []
        var seenNewIdentifiers: Set<String> = []
        for item in activeItems where !issuedIdentifiers.contains(item.stableIdentifier) {
            if seenNewIdentifiers.insert(item.stableIdentifier).inserted {
                itemsToIssue.append(item)
            }
        }

        var identifiersToRetract: [String] = []
        var updatedIssuedIdentifiers = issuedIdentifiers

        for identifier in issuedIdentifiers.sorted() {
            guard !activeIdentifiers.contains(identifier) else { continue }

            // Category from the leading segment, even for identifiers whose full format no
            // longer parses (e.g. the pre-slug "<category>.<id>" form): the fetched-category
            // guard must still protect an active alarm from being dropped by a failed status
            // request in the middle of an identifier-format migration.
            let category = NotificationItem.NotificationType(
                rawValue: String(identifier.prefix(while: { $0 != "." }))
            )

            if let category, surfacedCategories.contains(category) {
                // Absence is only trustworthy when the category's status response arrived.
                guard fetchedCategories.contains(category) else { continue }
            }
            // No-longer-surfaced categories and truly foreign identifiers are retracted
            // unconditionally.

            identifiersToRetract.append(identifier)
            updatedIssuedIdentifiers.remove(identifier)
        }

        updatedIssuedIdentifiers.formUnion(seenNewIdentifiers)

        return TandemAlertReconciliation(
            itemsToIssue: itemsToIssue,
            identifiersToRetract: identifiersToRetract,
            updatedIssuedIdentifiers: updatedIssuedIdentifiers
        )
    }
}
