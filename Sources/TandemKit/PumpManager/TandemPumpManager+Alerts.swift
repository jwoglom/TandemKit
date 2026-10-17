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
    var loopKitAlert: LoopKit.Alert {
        let content = LoopKit.Alert.Content(
            title: alertTitle,
            body: alertBody,
            acknowledgeActionButtonLabel: acknowledgeActionLabel
        )
        return LoopKit.Alert(
            identifier: TandemPumpManager.alertIdentifier(stableIdentifier),
            foregroundContent: content,
            backgroundContent: content,
            trigger: .immediate,
            interruptionLevel: severity.interruptionLevel
        )
    }
}

// MARK: - Alarm pump events

extension AlarmStatusResponse.AlarmResponseType {
    var pumpAlarmType: PumpAlarmType {
        switch self {
        case .OCCLUSION_ALARM, .OCCLUSION_ALARM2: return .occlusion
        case .EMPTY_CARTRIDGE_ALARM: return .noInsulin
        case .AUTO_OFF_ALARM: return .autoOff
        case .BATTERY_SHUTDOWN_ALARM: return .noPower
        case .RESUME_PUMP_ALARM, .RESUME_PUMP_ALARM2: return .noDelivery
        default: return .other(alertSlug == "other" ? String(describing: self) : alertSlug)
        }
    }
}

extension NewPumpEvent {
    /// The pump's alarm status gives no time, so it is dated when the driver read it.
    static func pumpAlarm(_ item: NotificationItem, date: Date) -> NewPumpEvent {
        let alarmType: PumpAlarmType = item.type == .malfunction
            ? .other("malfunction")
            : AlarmStatusResponse.AlarmResponseType(rawValue: Int(item.notificationId))?.pumpAlarmType ?? .other(item.name)
        let title = item.type == .malfunction
            ? String(
                format: String(localized: "Pump Malfunction %@", comment: "Pump Event title for a pump malfunction; the placeholder is the pump's fault code"),
                item.name
            )
            : item.title
        return NewPumpEvent(
            date: date,
            dose: nil,
            raw: "alarm \(item.stableIdentifier) \(ISO8601DateFormatter().string(from: date))".data(using: .utf8) ?? Data([]),
            title: title,
            type: .alarm,
            alarmType: alarmType
        )
    }

    static func pumpAlarmCleared(stableIdentifier: String, date: Date) -> NewPumpEvent {
        NewPumpEvent(
            date: date,
            dose: nil,
            raw: "alarmClear \(stableIdentifier) \(ISO8601DateFormatter().string(from: date))".data(using: .utf8) ?? Data([]),
            title: String(localized: "Alarm Cleared", comment: "Pump Event title for a pump alarm or malfunction that has cleared"),
            type: .alarmClear
        )
    }
}

extension TandemPumpManagerState {
    mutating func reconcileReportedPumpAlarms(
        active: [NotificationItem],
        fetchedCategories: Set<NotificationItem.NotificationType>
    ) -> TandemAlertReconciliation {
        let reconciliation = TandemAlertReconciler.reconcile(
            activeItems: active,
            fetchedCategories: fetchedCategories,
            issuedIdentifiers: reportedPumpAlarmIdentifiers,
            surfacedCategories: TandemPumpManager.pumpAlarmCategories
        )
        reportedPumpAlarmIdentifiers = reconciliation.updatedIssuedIdentifiers
        return reconciliation
    }
}

extension TandemPumpManager {
    /// Alerts and reminders are not faults, so only these reach the host's pump event log.
    static let pumpAlarmCategories: Set<NotificationItem.NotificationType> = [.alarm, .malfunction]

    /// Reports each alarm and malfunction the pump raises as an `.alarm` pump event, and an
    /// `.alarmClear` once a fetch that read its category no longer finds it.
    func reportPumpAlarms(from bundle: NotificationBundle) {
        let active = bundle.get().filter { Self.pumpAlarmCategories.contains($0.type) }
        let reconciliation = state.reconcileReportedPumpAlarms(active: active, fetchedCategories: bundle.fetchedCategories)
        guard !reconciliation.isEmpty else { return }

        let date = now
        let events = reconciliation.identifiersToRetract.map { NewPumpEvent.pumpAlarmCleared(stableIdentifier: $0, date: date) }
            + reconciliation.itemsToIssue.map { NewPumpEvent.pumpAlarm($0, date: date) }
        logger.info("Reporting pump alarms: \(events.map(\.title))")
        notifyDelegateStateUpdated()
        emitPumpEvents(events, replacePendingEvents: false)
    }
}

// MARK: - Alert reconciliation

extension TandemPumpManager {
    /// Loop and Trio register the manager as alert responder and sound vendor under its
    /// `pluginIdentifier` and look either up by an alert's `managerIdentifier`, so an alert under any
    /// other is never acknowledged on the pump.
    static func alertIdentifier(_ alertIdentifier: LoopKit.Alert.AlertIdentifier) -> LoopKit.Alert.Identifier {
        LoopKit.Alert.Identifier(managerIdentifier: pluginIdentifier, alertIdentifier: alertIdentifier)
    }

    /// What builds before `alertsIssuedUnderLegacyIdentifier` issued alerts under.
    static let legacyAlertManagerIdentifier = "Tandem"

    /// Retracts what the host holds under the legacy identifier, and forgets it was issued, so the
    /// reconcilers issue whatever still stands again under `pluginIdentifier`. Loop plays an
    /// unacknowledged, unretracted alert back at every launch. On the delegate queue.
    func retractLegacyAlerts(_ delegate: PumpManagerDelegate) {
        let issued = state
        guard issued.alertsIssuedUnderLegacyIdentifier else { return }

        var identifiers = issued.issuedAlertIdentifiers
        if issued.pumpClockSkewAlertIssued {
            identifiers.insert(Self.pumpClockSkewAlertIdentifier)
        }
        logger.info("Retracting alerts issued under \(Self.legacyAlertManagerIdentifier): \(identifiers.sorted())")
        for identifier in identifiers.sorted() {
            delegate.retractAlert(identifier: LoopKit.Alert.Identifier(
                managerIdentifier: Self.legacyAlertManagerIdentifier,
                alertIdentifier: identifier
            ))
        }
        state.issuedAlertIdentifiers = []
        state.pumpClockSkewAlertIssued = false
        state.alertsIssuedUnderLegacyIdentifier = false
    }

    /// Loop and Trio record an acknowledgement whether or not it reached the pump, so an alert whose
    /// dismissal failed is forgotten as issued: the reconciler issues it again while the pump raises it.
    func issueAgainAfterFailedAcknowledgement(_ alertIdentifier: String) {
        logger.warning("Acknowledgement of \(alertIdentifier) did not reach the pump; issuing it again while the pump raises it")
        pumpDelegate.notify { _ in
            guard self.state.issuedAlertIdentifiers.remove(alertIdentifier) != nil else { return }
            self.notifyDelegateStateUpdated()
        }
        reconcileLoopKitAlerts()
    }

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

        pumpDelegate.notify { delegate in
            guard let delegate else {
                self.logger.warning("No pump delegate; deferring alert reconciliation")
                return
            }
            self.retractLegacyAlerts(delegate)

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
                delegate.issueAlert(item.loopKitAlert)
            }

            for identifier in reconciliation.identifiersToRetract {
                self.logger.info("Retracting LoopKit alert \(identifier)")
                delegate.retractAlert(identifier: TandemPumpManager.alertIdentifier(identifier))
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
