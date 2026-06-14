import SwiftUI

class TandemKitAlertSettingsViewModel: ObservableObject {
    @Published var autoAcknowledgeBasalAlerts: Bool = false
    @Published var alertSnoozeEnabled: Bool = false
    @Published var alertSnoozeDurationMins: Int = 10

    private let pumpManager: TandemPumpManager?
    init(pumpManager: TandemPumpManager?) {
        self.pumpManager = pumpManager

        guard let pumpManager else {
            return
        }

        autoAcknowledgeBasalAlerts = pumpManager.state.autoAcknowledgeBasalAlerts
        alertSnoozeEnabled = pumpManager.state.alertSnoozeEnabled
        alertSnoozeDurationMins = Int(pumpManager.state.alertSnoozeDuration.minutes)
    }

    func setAutoAcknowledgeBasalAlerts(_ enabled: Bool) {
        pumpManager?.configureAutoAcknowledgeBasalAlerts(enabled)
        autoAcknowledgeBasalAlerts = enabled
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
