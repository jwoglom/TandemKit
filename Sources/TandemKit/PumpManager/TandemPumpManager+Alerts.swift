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
    /// pass ends here (Loop sync, qualifying events, the 5-minute poll, and post-dismiss
    /// refreshes all funnel through the same reconcile).
    func reconcileLoopKitAlerts() {
        let bundle = notificationBundle
        let reconciliation = TandemAlertReconciler.reconcile(
            activeItems: surfacedNotificationItems(from: bundle),
            fetchedCategories: bundle.fetchedCategories,
            issuedIdentifiers: state.issuedAlertIdentifiers,
            surfacedCategories: surfacedAlertCategories
        )

        guard !reconciliation.isEmpty else {
            return
        }

        state.issuedAlertIdentifiers = reconciliation.updatedIssuedIdentifiers
        notifyDelegateStateUpdated()

        let managerIdentifier = TandemPumpManager.managerIdentifier
        pumpDelegate.notify { delegate in
            guard let delegate else {
                self.logger.warning("No pump delegate, not issuing/retracting alerts...")
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
        }
    }

    public func configureForwardCGMAlerts(_ enabled: Bool) {
        state.forwardCGMAlerts = enabled
        notifyDelegateStateUpdated()

        logger.info("CGM alert forwarding \(enabled ? "enabled" : "disabled")")

        // Reconcile immediately so switching forwarding off retracts already-issued CGM
        // alerts without waiting for the next fetch (the reconciler retracts
        // no-longer-surfaced categories regardless of fetch state).
        reconcileLoopKitAlerts()
    }
}
