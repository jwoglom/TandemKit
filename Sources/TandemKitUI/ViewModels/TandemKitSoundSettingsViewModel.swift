import LoopKit
import SwiftUI

class TandemKitSoundSettingsViewModel: ObservableObject {
    @Published var buttonAnnun: Int = 0
    @Published var quickBolusAnnun: Int = 0
    @Published var bolusAnnun: Int = 0
    @Published var reminderAnnun: Int = 0
    @Published var alertAnnun: Int = 0
    @Published var alarmAnnun: Int = 0
    @Published var fillTubingAnnun: Int = 0

    private let pumpManager: TandemPumpManager?
    init(pumpManager: TandemPumpManager?) {
        self.pumpManager = pumpManager
        buttonAnnun = self.pumpManager?.state.buttonAnnun?.rawValue ?? 0
        quickBolusAnnun = self.pumpManager?.state.quickBolusAnnun?.rawValue ?? 0
        bolusAnnun = self.pumpManager?.state.bolusAnnun?.rawValue ?? 0
        reminderAnnun = self.pumpManager?.state.reminderAnnun?.rawValue ?? 0
        alertAnnun = self.pumpManager?.state.alertAnnun?.rawValue ?? 0
        alarmAnnun = self.pumpManager?.state.alarmAnnun?.rawValue ?? 0
        fillTubingAnnun = self.pumpManager?.state.fillTubingAnnun?.rawValue ?? 0

        pumpManager?.addStatusObserver(self, queue: DispatchQueue.main)
    }
}

extension TandemKitSoundSettingsViewModel: PumpManagerStatusObserver {
    func pumpManager(
        _: any LoopKit.PumpManager,
        didUpdate _: LoopKit.PumpManagerStatus,
        oldStatus _: LoopKit.PumpManagerStatus
    ) {
        guard let pumpManager = pumpManager else {
            return
        }

        DispatchQueue.main.async {
            self.buttonAnnun = pumpManager.state.buttonAnnun?.rawValue ?? 0
            self.quickBolusAnnun = pumpManager.state.quickBolusAnnun?.rawValue ?? 0
            self.bolusAnnun = pumpManager.state.bolusAnnun?.rawValue ?? 0
            self.reminderAnnun = pumpManager.state.reminderAnnun?.rawValue ?? 0
            self.alertAnnun = pumpManager.state.alertAnnun?.rawValue ?? 0
            self.alarmAnnun = pumpManager.state.alarmAnnun?.rawValue ?? 0
            self.fillTubingAnnun = pumpManager.state.fillTubingAnnun?.rawValue ?? 0
        }
    }
}
