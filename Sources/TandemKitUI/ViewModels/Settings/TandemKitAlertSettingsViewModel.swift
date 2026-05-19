import SwiftUI

class TandemKitAlertSettingsViewModel: ObservableObject {
    @Published var autoAcknowledgeBasalAlerts: Bool = false
    @Published var alertSnoozeEnabled: Bool = false
    @Published var alertSnoozeDurationMins: Int = 10

    private let pumpManager: TandemPumpManager?
    init(pumpManager: TandemPumpManager?) {
        self.pumpManager = pumpManager
    }

    func setAutoAcknowledgeBasalAlerts(_ enabled: Bool) {
        pumpManager?.configureAutoAcknowledgeBasalAlerts(enabled)
        autoAcknowledgeBasalAlerts = enabled
    }

    func setAlertSnooze(enabled: Bool, durationMins: Int) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.pumpManager?.setAlertSnooze(enabled: enabled, durationMins: durationMins)
            DispatchQueue.main.async {
                self?.alertSnoozeEnabled = enabled
                self?.alertSnoozeDurationMins = durationMins
            }
        }
    }
}
