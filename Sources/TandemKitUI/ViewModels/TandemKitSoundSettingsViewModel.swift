import LoopKit
import SwiftUI
import TandemCore

class TandemKitSoundSettingsViewModel: ObservableObject {
    @Published var generalAnnun: Int = 0 { didSet { checkDirtyState() } }
    @Published var quickBolusAnnun: Int = 0 { didSet { checkDirtyState() } }
    @Published var reminderAnnun: Int = 0 { didSet { checkDirtyState() } }
    @Published var alertAnnun: Int = 0 { didSet { checkDirtyState() } }
    @Published var alarmAnnun: Int = 0 { didSet { checkDirtyState() } }

    @Published var isLoading: Bool = false
    @Published var isDirty: Bool = false
    @Published var isDisabled: Bool = false

    var originalGeneralAnnun: Int = 0
    var originalQuickBolusAnnun: Int = 0
    var originalBolusAnnun: Int = 0
    var originalReminderAnnun: Int = 0
    var originalAlertAnnun: Int = 0
    var originalAlarmAnnun: Int = 0
    var originalFillTubingAnnun: Int = 0

    private let pumpManager: TandemPumpManager?
    let onSubmit: (() -> Void)?
    init(pumpManager: TandemPumpManager?, onSubmit: (() -> Void)?) {
        self.pumpManager = pumpManager
        self.onSubmit = onSubmit

        guard let pumpManager = pumpManager else {
            return
        }

        let status = pumpManager.status
        self.pumpManager(pumpManager, didUpdate: status, oldStatus: status)
        pumpManager.addStatusObserver(self, queue: DispatchQueue.main)
    }

    deinit {
        pumpManager?.removeStatusObserver(self)
    }

    func submit() {
        if let onSubmit = onSubmit {
            guard let pumpManager = self.pumpManager else {
                onSubmit()
                return
            }

            var state = pumpManager.state
            state.generalAnnun = PumpGlobalsResponse.AnnunciationEnum(rawValue: generalAnnun) ?? .audioHigh
            state.quickBolusAnnun = PumpGlobalsResponse.AnnunciationEnum(rawValue: quickBolusAnnun) ?? .audioHigh
            state.reminderAnnun = PumpGlobalsResponse.AnnunciationEnum(rawValue: reminderAnnun) ?? .audioHigh
            state.alertAnnun = PumpGlobalsResponse.AnnunciationEnum(rawValue: alertAnnun) ?? .audioHigh
            state.alarmAnnun = PumpGlobalsResponse.AnnunciationEnum(rawValue: alarmAnnun) ?? .audioHigh
            pumpManager.lockedState.value = state

            onSubmit()
            return
        }

        var changedBits: [PumpSoundChangeBitmask] = []
        if originalQuickBolusAnnun != quickBolusAnnun { changedBits.append(.quickBolusAnnun) }
        if originalGeneralAnnun != generalAnnun { changedBits.append(.generalAnnun) }
        if originalReminderAnnun != reminderAnnun { changedBits.append(.reminderAnnun) }
        if originalAlertAnnun != alertAnnun { changedBits.append(.alertAnnun) }
        if originalAlarmAnnun != alarmAnnun { changedBits.append(.alarmAnnun) }

        guard !changedBits.isEmpty else {
            return
        }

        let request = SetPumpSoundsRequest(
            quickBolusAnnunRaw: quickBolusAnnun,
            generalAnnunRaw: generalAnnun,
            reminderAnnunRaw: reminderAnnun,
            alertAnnunRaw: alertAnnun,
            alarmAnnunRaw: alarmAnnun,
            cgmAlertAnnunA: 0,
            cgmAlertAnnunB: 0,
            changeBitmaskRaw: PumpSoundChangeBitmask.toBitmask(changedBits)
        )

        isDirty = false
        isLoading = true
        pumpManager?.setPumpSound(request: request)

        isLoading = false

        originalGeneralAnnun = generalAnnun
        originalQuickBolusAnnun = quickBolusAnnun
        originalReminderAnnun = reminderAnnun
        originalAlertAnnun = alertAnnun
        originalAlarmAnnun = alarmAnnun
    }

    func checkDirtyState() {
        DispatchQueue.main.async {
            self.isDirty = (
                self.originalQuickBolusAnnun != self.quickBolusAnnun ||
                    self.originalGeneralAnnun != self.generalAnnun ||
                    self.originalReminderAnnun != self.reminderAnnun ||
                    self.originalAlertAnnun != self.alertAnnun ||
                    self.originalAlarmAnnun != self.alarmAnnun
            )

            self.isDisabled = !self.isDirty && self.onSubmit == nil
        }
    }
}

extension TandemKitSoundSettingsViewModel: PumpManagerStatusObserver {
    func pumpManager(
        _: any LoopKit.PumpManager,
        didUpdate _: LoopKit.PumpManagerStatus,
        oldStatus _: LoopKit.PumpManagerStatus
    ) {
        guard let pumpManager = pumpManager, !isDirty else {
            return
        }

        DispatchQueue.main.async {
            self.quickBolusAnnun = pumpManager.state.quickBolusAnnun?.rawValue ?? 0
            self.generalAnnun = pumpManager.state.generalAnnun?.rawValue ?? 0
            self.reminderAnnun = pumpManager.state.reminderAnnun?.rawValue ?? 0
            self.alertAnnun = pumpManager.state.alertAnnun?.rawValue ?? 0
            self.alarmAnnun = pumpManager.state.alarmAnnun?.rawValue ?? 0

            self.originalGeneralAnnun = self.generalAnnun
            self.originalQuickBolusAnnun = self.quickBolusAnnun
            self.originalReminderAnnun = self.reminderAnnun
            self.originalAlertAnnun = self.alertAnnun
            self.originalAlarmAnnun = self.alarmAnnun
        }
    }
}
