import CoreBluetooth
import LoopKit
import SwiftUI
import TandemCore

class TandemKitNotificationsViewModel: ObservableObject {
    private let log = TandemLogger(category: "TandemKitNotificationsViewModel")
    private var pumpManager: TandemPumpManager?

    @Published var notifications: [NotificationItem] = []
    @Published var isRefreshing = false
    @Published var lastRefreshTime: Date?
    @Published var errorMessage: String?

    /// Uses a local bundle for fetching, then syncs to the pump manager's shared bundle
    private var notificationBundle = NotificationBundle()

    init(_ pumpManager: TandemPumpManager? = nil) {
        self.pumpManager = pumpManager

        // Initialize with current notifications from the pump manager's shared bundle
        if let manager = pumpManager {
            let items = manager.notificationBundle.get()
            notifications = items
        }
    }

    var pumpComm: PumpComm? {
        pumpManager?.tandemPump.pumpComm
    }

    func sendMessage(message: Message) -> Message? {
        guard let transport = pumpManager?.pairedTransport else {
            return nil
        }

        return try? transport.sendMessage(message)
    }

    func refreshNotifications() {
        isRefreshing = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Create a fresh bundle for this fetch
            let freshBundle = NotificationBundle()

            // Send all notification status requests
            for request in NotificationBundle.allRequests() {
                if let response = self.sendMessage(message: request) {
                    if NotificationBundle.isNotificationResponse(response) {
                        freshBundle.add(response)
                    }
                }
            }

            // Update our local reference
            self.notificationBundle = freshBundle

            // Sync the fresh bundle to the pump manager's shared state
            // This ensures the badge count in settings stays in sync with the list here
            self.pumpManager?.updateNotificationBundle(freshBundle)

            // Auto-acknowledge basal alerts if enabled
            if self.pumpManager?.autoAcknowledgeBasalAlerts == true {
                self.autoAcknowledgeBasalAlerts()
            }

            // Get all active notifications
            let items = freshBundle.get()

            DispatchQueue.main.async {
                self.notifications = items
                self.isRefreshing = false
                self.lastRefreshTime = Date()
            }
        }
    }

    private func autoAcknowledgeBasalAlerts() {
        guard let alertResponse = notificationBundle.alertStatusResponse else { return }

        let basalAlertsToAck = alertResponse.alerts.intersection(
            AlertStatusResponse.AlertResponseType.basalAlertsToIgnoreWhenLooping
        )

        guard !basalAlertsToAck.isEmpty else { return }

        log.info("[auto-ack] Found \(basalAlertsToAck.count) basal alert(s) to acknowledge")

        for alert in basalAlertsToAck {
            let request = DismissNotificationRequest(
                notificationType: .alert,
                notificationId: UInt32(alert.rawValue)
            )

            if let response = sendMessage(message: request) as? DismissNotificationResponse {
                if response.status == 0 {
                    log.info("[auto-ack] Successfully acknowledged \(alert)")
                } else {
                    log.warning("[auto-ack] Failed to acknowledge \(alert): status=\(response.status)")
                }
            }
        }

        // Re-fetch alert status after acknowledging
        if let response = sendMessage(message: AlertStatusRequest()) as? AlertStatusResponse {
            notificationBundle.add(response)
        }
    }

    func dismissNotification(_ item: NotificationItem) {
        guard let dismissType = item.type.dismissType else {
            log.error("Cannot dismiss notification of type \(item.type)")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let request = DismissNotificationRequest(
                notificationType: dismissType,
                notificationId: item.notificationId
            )

            if let response = self.sendMessage(message: request) as? DismissNotificationResponse {
                if response.status == 0 {
                    // Success - remove from local list immediately for better UX
                    DispatchQueue.main.async {
                        self.notifications.removeAll { $0.id == item.id }
                    }

                    // Refresh after a short delay to get updated pump state
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.refreshNotifications()
                    }
                } else {
                    self.log.error("Failed to dismiss notification: status=\(response.status)")
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to dismiss notification (status: \(response.status))"
                    }
                }
            } else {
                self.log.error("Failed to dismiss notification: no response")
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to dismiss notification"
                }
            }
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
