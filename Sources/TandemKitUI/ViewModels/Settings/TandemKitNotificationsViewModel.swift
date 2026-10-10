import Combine
import CoreBluetooth
import Foundation
import LoopKit

class TandemKitNotificationsViewModel: ObservableObject {
    private let log = TandemLogger(category: "TandemKitNotificationsViewModel")
    private var pumpManager: TandemPumpManager?

    @Published var notifications: [NotificationItem] = []
    @Published var isRefreshing = false
    @Published var lastRefreshTime: Date?
    @Published var errorMessage: String?

    /// Callers waiting for a refresh that reflects state read after they asked. Drained on the
    /// main queue when the read they are waiting on finishes; see `refreshNotifications`.
    private var pendingCompletions: [() -> Void] = []
    /// Set when a refresh is requested while another is in flight, so one more read runs after it.
    private var refreshQueuedWhileInFlight = false

    init(_ pumpManager: TandemPumpManager? = nil) {
        self.pumpManager = pumpManager

        // Initialize with current notifications from the pump manager's shared bundle
        if let manager = pumpManager {
            notifications = manager.notificationBundle.get()
        }
    }

    /// Re-reads the pump's notification state and publishes it, calling `completion` on the main
    /// queue once the list reflects a read that started no earlier than this call.
    ///
    /// A read that was already in flight never answers for this call: it may have been sent to the
    /// pump before whatever prompted the call happened (e.g. the pump stopping a tubing fill), so
    /// it cannot speak for it. One more read is run as soon as the current one returns.
    ///
    /// This reads only the notification surfaces, not the pump's full status, so it is cheap
    /// enough to call as often as a screen needs. Periodic polling should use
    /// `refreshNotificationsIfIdle()` instead, which has no event to be newer than.
    func refreshNotifications(completion: (() -> Void)? = nil) {
        guard let pumpManager else {
            log.error("No pumpManager")
            completion?()
            return
        }

        if let completion {
            pendingCompletions.append(completion)
        }

        guard !isRefreshing else {
            log.info("[TIMING] Refresh already in flight, queueing another pass behind it")
            refreshQueuedWhileInFlight = true
            return
        }

        log.info("[TIMING] refreshNotifications() called, isRefreshing=\(isRefreshing)")

        startRefresh(pumpManager)
    }

    /// Refreshes unless a read is already talking to the pump.
    ///
    /// For periodic polling: a read already in flight is as good as the one this tick would start,
    /// and another tick is coming, so there is nothing to gain by queueing one behind it.
    func refreshNotificationsIfIdle() {
        guard !isRefreshing else {
            log.info("[TIMING] Skipping poll; a read is already in flight")
            return
        }

        refreshNotifications()
    }

    private func startRefresh(_ pumpManager: TandemPumpManager) {
        isRefreshing = true
        errorMessage = nil

        // Everything registered before this read starts is answered by it. Anything registered
        // while it runs stays queued for the next pass, so a caller is never handed a result read
        // before it asked, and a busy poll cannot starve one that is already waiting.
        let awaiting = pendingCompletions
        pendingCompletions = []

        pumpManager.refreshNotifications { succeeded in
            DispatchQueue.main.async {
                self.notifications = pumpManager.notificationBundle.get()
                self.isRefreshing = false
                if succeeded {
                    self.lastRefreshTime = Date()
                }

                awaiting.forEach { $0() }

                if self.refreshQueuedWhileInFlight {
                    self.refreshQueuedWhileInFlight = false
                    self.refreshNotifications()
                }
            }
        }
    }

    /// `completion` runs on the main queue once the pump has answered and the list is updated.
    func dismissNotification(_ item: NotificationItem, completion: ((Bool) -> Void)? = nil) {
        guard let pumpManager else {
            completion?(false)
            return
        }

        pumpManager.dismissNotification(notification: item) { success in
            guard success else {
                DispatchQueue.main.async {
                    self.errorMessage = String(localized: "Failed to dismiss notification", comment: "dismiss notification error")
                    completion?(false)
                }
                return
            }

            // Matched by what it is, not by `id`: every read builds new items, so a refresh landing
            // while the pump answers leaves `item` with an id nothing in the list carries.
            DispatchQueue.main.async {
                self.notifications.removeAll { $0.type == item.type && $0.notificationId == item.notificationId }
                completion?(true)
            }

            // Refresh after a short delay to get updated pump state. This has to reflect the
            // pump after the dismissal, so it must not settle for a read already in flight.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.refreshNotifications()
            }
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
