import CoreBluetooth
import LoopKit
import SwiftUI
import TandemCore

class TandemKitNotificationsViewModel: ObservableObject {
    private let log = PumpLogger(label: "TandemKitNotificationsViewModel")
    private var pumpManager: TandemPumpManager?

    @Published var notifications: [NotificationItem] = []
    @Published var isRefreshing = false
    @Published var lastRefreshTime: Date?
    @Published var errorMessage: String?

    private let notificationBundle = NotificationBundle()

    init(_ pumpManager: TandemPumpManager? = nil) {
        self.pumpManager = pumpManager
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

            // Send all notification status requests
            for request in NotificationBundle.allRequests() {
                if let response = self.sendMessage(message: request) {
                    if NotificationBundle.isNotificationResponse(response) {
                        self.notificationBundle.add(response)
                    }
                }
            }

            // Get all active notifications
            let items = self.notificationBundle.get()

            DispatchQueue.main.async {
                self.notifications = items
                self.isRefreshing = false
                self.lastRefreshTime = Date()
            }
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
