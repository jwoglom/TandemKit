import Combine
import Foundation

class TandemKitAlertSettingsViewModel: ObservableObject {
    @Published var alertSnoozeEnabled: Bool = false
    @Published var alertSnoozeDurationMins: Int = 10
    @Published var forwardCGMAlerts: Bool = false
    @Published var saveError: String?

    private let pumpManager: TandemPumpManager?
    init(pumpManager: TandemPumpManager?) {
        self.pumpManager = pumpManager

        guard let pumpManager else {
            return
        }

        showAlertSnooze(from: pumpManager.state)
        forwardCGMAlerts = pumpManager.state.forwardCGMAlerts
    }

    func setForwardCGMAlerts(_ enabled: Bool) {
        pumpManager?.configureForwardCGMAlerts(enabled)
        forwardCGMAlerts = enabled
    }

    func setAlertSnooze(enabled: Bool, durationMins: Int) {
        guard let pumpManager else {
            return
        }

        saveError = nil
        pumpManager.setAlertSnooze(enabled: enabled, durationMins: durationMins) { accepted in
            DispatchQueue.main.async {
                // The driver records the setting only once the pump accepts it.
                self.showAlertSnooze(from: pumpManager.state)
                if !accepted {
                    self.saveError = String(
                        localized: "Could not save the alert snooze setting to the pump.",
                        comment: "Error shown when saving the alert snooze setting fails"
                    )
                }
            }
        }
    }

    private func showAlertSnooze(from state: TandemPumpManagerState) {
        alertSnoozeEnabled = state.alertSnoozeEnabled
        alertSnoozeDurationMins = Int(state.alertSnoozeDuration.minutes)
    }
}
