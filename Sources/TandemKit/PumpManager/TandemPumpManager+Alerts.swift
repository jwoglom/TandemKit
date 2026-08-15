import Foundation
import LoopKit

// MARK: - LoopKit alert mapping

extension PumpNotificationSeverity {
    var interruptionLevel: LoopKit.Alert.InterruptionLevel {
        switch self {
        case .informational:
            return .active
        case .timeSensitive:
            return .timeSensitive
        case .critical:
            // Delivered as a critical alert only when the hosting app holds the
            // critical-alerts entitlement; iOS downgrades it otherwise.
            return .critical
        }
    }
}

extension NotificationItem {
    func loopKitAlert(managerIdentifier: String) -> LoopKit.Alert {
        let content = LoopKit.Alert.Content(
            title: alertTitle,
            body: alertBody,
            acknowledgeActionButtonLabel: acknowledgeActionLabel
        )
        return LoopKit.Alert(
            identifier: LoopKit.Alert.Identifier(
                managerIdentifier: managerIdentifier,
                alertIdentifier: stableIdentifier
            ),
            foregroundContent: content,
            backgroundContent: content,
            trigger: .immediate,
            interruptionLevel: severity.interruptionLevel
        )
    }
}

// MARK: - Alert reconciliation

extension TandemPumpManager {
    /// Notification categories currently forwarded to LoopKit as alerts. Alarms and
    /// malfunctions mean stopped/compromised delivery; alerts are actionable. CGM alerts
    /// are opt-in and reminders stay in-app only.
    var surfacedAlertCategories: Set<NotificationItem.NotificationType> {
        var categories: Set<NotificationItem.NotificationType> = [.alert, .alarm, .malfunction]
        if state.forwardCGMAlerts {
            categories.insert(.cgmAlert)
        }
        return categories
    }

    /// Active pump notifications that should exist as LoopKit alerts right now.
    func surfacedNotificationItems(from bundle: NotificationBundle) -> [NotificationItem] {
        bundle.get().filter { item in
            guard surfacedAlertCategories.contains(item.type) else {
                return false
            }
            if state.autoAcknowledgeBasalAlerts, item.type == .alert,
               let alertType = AlertStatusResponse.AlertResponseType(rawValue: Int(item.notificationId)),
               AlertStatusResponse.AlertResponseType.basalAlertsToIgnoreWhenLooping.contains(alertType)
            {
                // The driver silently dismisses these on the pump; don't notify the user.
                return false
            }
            return true
        }
    }

    /// Diffs the freshly-fetched notification bundle against the persisted issued-alert set
    /// and issues/retracts LoopKit alerts through the delegate. Every `fetchNotifications()`
    /// pass ends here (Loop sync, qualifying events, and post-dismiss refreshes all funnel
    /// through the same reconcile).
    ///
    /// The diff, the delegate calls, and the `issuedAlertIdentifiers` update all run together
    /// inside `pumpDelegate.notify`, for two reasons:
    /// - The persisted set must never get ahead of delivery. If the delegate is not attached
    ///   yet (e.g. a qualifying event racing app launch), recording an alarm as issued without
    ///   having delivered it would silence that alarm on every later pass. Instead the whole
    ///   pass is deferred untouched, so the next fetch delivers it.
    /// - `notify` runs on the single serialized delegate queue, so concurrent reconciles
    ///   (sync-driven on the command queue vs. settings-driven on the main thread) cannot
    ///   interleave their read-modify-writes of `issuedAlertIdentifiers` and lose updates.
    func reconcileLoopKitAlerts() {
        // Snapshot the bundle-derived inputs up front; the issued set is read inside the
        // serialized block so the diff always runs against its latest value.
        let bundle = notificationBundle
        let activeItems = surfacedNotificationItems(from: bundle)
        let fetchedCategories = bundle.fetchedCategories
        let surfacedCategories = surfacedAlertCategories
        let managerIdentifier = TandemPumpManager.managerIdentifier

        pumpDelegate.notify { delegate in
            guard let delegate else {
                self.logger.warning("No pump delegate; deferring alert reconciliation")
                return
            }

            let reconciliation = TandemAlertReconciler.reconcile(
                activeItems: activeItems,
                fetchedCategories: fetchedCategories,
                issuedIdentifiers: self.state.issuedAlertIdentifiers,
                surfacedCategories: surfacedCategories
            )

            guard !reconciliation.isEmpty else {
                return
            }

            for item in reconciliation.itemsToIssue {
                self.logger.info("Issuing LoopKit alert \(item.stableIdentifier)")
                delegate.issueAlert(item.loopKitAlert(managerIdentifier: managerIdentifier))
            }

            for identifier in reconciliation.identifiersToRetract {
                self.logger.info("Retracting LoopKit alert \(identifier)")
                delegate.retractAlert(identifier: LoopKit.Alert.Identifier(
                    managerIdentifier: managerIdentifier,
                    alertIdentifier: identifier
                ))
            }

            self.state.issuedAlertIdentifiers = reconciliation.updatedIssuedIdentifiers
            self.notifyDelegateStateUpdated()
        }
    }

    public func configureForwardCGMAlerts(_ enabled: Bool) {
        state.forwardCGMAlerts = enabled
        notifyDelegateStateUpdated()

        logger.info("CGM alert forwarding \(enabled ? "enabled" : "disabled")")

        if enabled {
            // Don't issue time-sensitive alerts from a possibly hours-stale bundle: read the
            // pump's current state instead, which reconciles (and issues) on completion.
            bluetooth.ensureConnected { error in
                if let error {
                    // The next sync or qualifying event picks the new setting up.
                    self.logger.warning("CGM alert forwarding enabled but fetch failed: \(error.localizedDescription)")
                    return
                }
                self.fetchNotifications()
            }
        } else {
            // Retract-only direction: the reconciler drops no-longer-surfaced categories
            // regardless of fetch state, so this is safe against a stale bundle.
            reconcileLoopKitAlerts()
        }
    }
}
