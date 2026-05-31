import CoreBluetooth
import LoopKit
import SwiftUI

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
            notifications = manager.notificationBundle.get()
        }
    }

    func refreshNotifications() {
        guard !isRefreshing else {
            log.info("[TIMING] Already refreshing notifications, skipping duplicate request")
            return
        }

        log.info("[TIMING] refreshNotifications() called, isRefreshing=\(isRefreshing)")

        guard let pumpManager else {
            log.error("No pumpManager")
            return
        }

        isRefreshing = true
        errorMessage = nil

        pumpManager.ensureCurrentPumpData { _ in
            DispatchQueue.main.async {
                self.notifications = pumpManager.notificationBundle.get()
                self.isRefreshing = false
            }
        }
    }

    func dismissNotification(_ item: NotificationItem) {
        pumpManager?.dismissNotification(notification: item) { success in
            guard success else {
                DispatchQueue.main.async {
                    self.errorMessage = String(localized: "Failed to dismiss notification", comment: "dismiss notification error")
                }
                return
            }

            DispatchQueue.main.async {
                self.notifications.removeAll { $0.id == item.id }
            }

            // Refresh after a short delay to get updated pump state
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.refreshNotifications()
            }
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
