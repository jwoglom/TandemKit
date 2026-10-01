import Combine
import Foundation
import LoopKit

class TandemKitSoundSettingsViewModel: ObservableObject {
    private static let defaultSound = PumpGlobalsResponse.AnnunciationEnum.vibrate

    @Published var generalAnnun: Int = TandemKitSoundSettingsViewModel.defaultSound.rawValue { didSet { checkDirtyState() } }
    @Published var quickBolusAnnun: Int = TandemKitSoundSettingsViewModel.defaultSound.rawValue { didSet { checkDirtyState() } }
    @Published var reminderAnnun: Int = TandemKitSoundSettingsViewModel.defaultSound.rawValue { didSet { checkDirtyState() } }
    @Published var alertAnnun: Int = TandemKitSoundSettingsViewModel.defaultSound.rawValue { didSet { checkDirtyState() } }
    @Published var alarmAnnun: Int = TandemKitSoundSettingsViewModel.defaultSound.rawValue { didSet { checkDirtyState() } }

    @Published var isLoading: Bool = false
    @Published var isDirty: Bool = false
    @Published var isDisabled: Bool = false
    @Published var saveError: String?

    var originalGeneralAnnun: Int = TandemKitSoundSettingsViewModel.defaultSound.rawValue
    var originalQuickBolusAnnun: Int = TandemKitSoundSettingsViewModel.defaultSound.rawValue
    var originalReminderAnnun: Int = TandemKitSoundSettingsViewModel.defaultSound.rawValue
    var originalAlertAnnun: Int = TandemKitSoundSettingsViewModel.defaultSound.rawValue
    var originalAlarmAnnun: Int = TandemKitSoundSettingsViewModel.defaultSound.rawValue

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

            pumpManager.state.generalAnnun = PumpGlobalsResponse.AnnunciationEnum(rawValue: generalAnnun) ?? Self.defaultSound
            pumpManager.state.quickBolusAnnun = PumpGlobalsResponse.AnnunciationEnum(rawValue: quickBolusAnnun) ?? Self.defaultSound
            pumpManager.state.reminderAnnun = PumpGlobalsResponse.AnnunciationEnum(rawValue: reminderAnnun) ?? Self.defaultSound
            pumpManager.state.alertAnnun = PumpGlobalsResponse.AnnunciationEnum(rawValue: alertAnnun) ?? Self.defaultSound
            pumpManager.state.alarmAnnun = PumpGlobalsResponse.AnnunciationEnum(rawValue: alarmAnnun) ?? Self.defaultSound
            pumpManager.state.pumpSoundsAwaitingWrite = true
            pumpManager.notifyDelegateStateUpdated()

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
        saveError = nil
        pumpManager?.setPumpSound(request: request) { accepted in
            DispatchQueue.main.async {
                self.isLoading = false

                guard accepted else {
                    self.showPumpSounds()
                    self.saveError = String(
                        localized: "Could not save the sound settings to the pump.",
                        comment: "Error shown when saving the pump sound settings fails"
                    )
                    return
                }

                self.originalGeneralAnnun = self.generalAnnun
                self.originalQuickBolusAnnun = self.quickBolusAnnun
                self.originalReminderAnnun = self.reminderAnnun
                self.originalAlertAnnun = self.alertAnnun
                self.originalAlarmAnnun = self.alarmAnnun
            }
        }
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

    private func showPumpSounds() {
        guard let pumpManager = pumpManager else {
            return
        }

        quickBolusAnnun = (pumpManager.state.quickBolusAnnun ?? Self.defaultSound).rawValue
        generalAnnun = (pumpManager.state.generalAnnun ?? Self.defaultSound).rawValue
        reminderAnnun = (pumpManager.state.reminderAnnun ?? Self.defaultSound).rawValue
        alertAnnun = (pumpManager.state.alertAnnun ?? Self.defaultSound).rawValue
        alarmAnnun = (pumpManager.state.alarmAnnun ?? Self.defaultSound).rawValue

        originalGeneralAnnun = generalAnnun
        originalQuickBolusAnnun = quickBolusAnnun
        originalReminderAnnun = reminderAnnun
        originalAlertAnnun = alertAnnun
        originalAlarmAnnun = alarmAnnun
    }
}

extension TandemKitSoundSettingsViewModel: PumpManagerStatusObserver {
    func pumpManager(
        _: any LoopKit.PumpManager,
        didUpdate _: LoopKit.PumpManagerStatus,
        oldStatus _: LoopKit.PumpManagerStatus
    ) {
        guard !isDirty else {
            return
        }

        DispatchQueue.main.async {
            self.showPumpSounds()
        }
    }
}
