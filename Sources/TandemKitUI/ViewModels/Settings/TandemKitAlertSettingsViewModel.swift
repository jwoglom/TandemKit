import SwiftUI

class TandemKitAlertSettingsViewModel: ObservableObject {
    @Published var alertSnoozeEnabled: Bool = false
    @Published var alertSnoozeDurationMins: Int = 10
    @Published var forwardCGMAlerts: Bool = false

    private let pumpManager: TandemPumpManager?
    init(pumpManager: TandemPumpManager?) {
        self.pumpManager = pumpManager

        guard let pumpManager else {
            return
        }

        alertSnoozeEnabled = pumpManager.state.alertSnoozeEnabled
        alertSnoozeDurationMins = Int(pumpManager.state.alertSnoozeDuration.minutes)
        forwardCGMAlerts = pumpManager.state.forwardCGMAlerts
    }

    func setForwardCGMAlerts(_ enabled: Bool) {
        pumpManager?.configureForwardCGMAlerts(enabled)
        forwardCGMAlerts = enabled
    }

    func setAlertSnooze(enabled: Bool, durationMins: Int) {
        pumpManager?.setAlertSnooze(enabled: enabled, durationMins: durationMins) { _ in
            DispatchQueue.main.async {
                self.alertSnoozeEnabled = enabled
                self.alertSnoozeDurationMins = durationMins
            }
        }
    }
}
