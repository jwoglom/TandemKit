import CoreBluetooth
import LoopKit
import SwiftUI

enum CommandFailure: Int, Identifiable {
    case resume
    case suspend
    case controlIQ
    case exerciseMode
    case sleepMode
    case stopTempRate
    case playSound
    case alertSnooze

    var id: Int { rawValue }
}

class TandemKitSettingsViewModel: ObservableObject {
    private let log = TandemLogger(category: "TandemKitSettingsViewModel")
    private var pumpManager: TandemPumpManager?
    private var nextStep: () -> Void
    let openPumpInformation: () -> Void
    let openNotifications: () -> Void
    let openInsulinType: () -> Void
    let openSoundSettings: () -> Void
    let openCartridgeChange: () -> Void
    let openFillTubing: () -> Void
    let openFillCannula: () -> Void
    let openCgmSettings: () -> Void
    let openControlIQSettings: () -> Void
    let openQuickBolus: () -> Void
    let openAlertSettings: () -> Void

    var appName: String { HostApp.current.appName }
    var algorithmName: String { HostApp.current.diyAlgorithmName }

    @Published var pumpState: PumpState? = nil
    @Published var controlIQEnabled: Bool = false
    @Published var isClosedLoopEnabled: Bool = false
    @Published var currentProfileBaseBasalRate: Double? = nil
    @Published var currentBasalRateForDisplay: String = ""
    @Published var batteryPercentage: String? = nil
    @Published var pumpTimeCheckedAt: String = ""
    @Published var currentPumpTime: String = ""
    @Published var reservoirUnitsText: String? = nil
    @Published var controlIQUserMode: TandemPumpManagerState.ControlIQUserMode? = nil
    @Published var reservoirValue: ReservoirValue?
    @Published var quickBolusEnabled: Bool? = nil
    @Published var notificationCount: Int = 0
    @Published var suspendResumeText: String? = nil
    @Published var algorithmModeText: String = ""
    @Published var sleepModeText: String = ""
    @Published var exerciseModeText: String = ""
    @Published var controlIqModeText: String = ""
    @Published var isUpdatingPumpState = false
    @Published var showPumpTimeSyncWarning = false
    @Published var isUpdatingTime = false
    @Published var showingTimeSyncConfirmation = false
    @Published var commandFailure: CommandFailure?
    @Published var basalDose: UnfinalizedDose?
    @Published var scheduledBasal: Double = 0
    @Published var showingDeleteConfirmation = false
    @Published var showingDebugDetails = false
    @Published var autoAcknowledgeBasalAlerts: Bool = false
    @Published var isConnected: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var useSilentMode: Bool = false
    @Published var isPlayingSound: Bool = false
    @Published var useControlIQ: Bool = false
    @Published var showReenableClosedLoopPrompt: Bool = false
    @Published var showNoCGMWarning: Bool = false
    @Published var isCGMActiveOnPump: Bool = false
    @Published var pendingEnableClosedLoop: Bool = false

    private var numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 0
        formatter.positiveSuffix = "%"
        return formatter
    }()

    private let dateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()

    init(
        _ pumpManager: TandemPumpManager? = nil,
        nextStep: @escaping () -> Void,
        openPumpInformation: @escaping () -> Void,
        openNotifications: @escaping () -> Void,
        openInsulinType: @escaping () -> Void,
        openSoundSettings: @escaping () -> Void,
        openCartridgeChange: @escaping () -> Void,
        openFillTubing: @escaping () -> Void,
        openFillCannula: @escaping () -> Void,
        openCgmSettings: @escaping () -> Void,
        openControlIQSettings: @escaping () -> Void,
        openQuickBolus: @escaping () -> Void,
        openAlertSettings: @escaping () -> Void
    ) {
        self.pumpManager = pumpManager
        self.nextStep = nextStep
        self.openPumpInformation = openPumpInformation
        self.openNotifications = openNotifications
        self.openInsulinType = openInsulinType
        self.openSoundSettings = openSoundSettings
        self.openCartridgeChange = openCartridgeChange
        self.openFillTubing = openFillTubing
        self.openFillCannula = openFillCannula
        self.openCgmSettings = openCgmSettings
        self.openControlIQSettings = openControlIQSettings
        self.openQuickBolus = openQuickBolus
        self.openAlertSettings = openAlertSettings
        autoAcknowledgeBasalAlerts = pumpManager?.autoAcknowledgeBasalAlerts ?? false
        useSilentMode = pumpManager?.state.useSilentTones ?? false
        useControlIQ = pumpManager?.state.useControlIQ ?? false
        reservoirValue = pumpManager?.reservoirLevel
        isConnected = false
        showPumpTimeSyncWarning = pumpManager?.state.showPumpTimeSyncWarning ?? false
        basalDose = pumpManager?.state.basalDose

        if let pumpManager {
            pumpManager.addStatusObserver(self, queue: .main)
            self.pumpManager(pumpManager, didUpdate: pumpManager.status, oldStatus: pumpManager.status)
        }
    }

    // MARK: - Refresh Methods

    func refreshPumpStatus() {
        guard let pumpManager else {
            log.debug("Skipping TandemPumpSettings refresh – pump not connected/paired")
            return
        }

        guard !isRefreshing else { return }
        isRefreshing = true

        pumpManager.syncPumpData { _ in
            DispatchQueue.main.async {
                self.isRefreshing = false
            }
        }
    }

    func suspendResumeButtonPressed() {
        guard let pumpManager else {
            return
        }

        if pumpManager.state.basalDose.type == .suspend {
            pumpManager.resumeDelivery { error in
                DispatchQueue.main.async {
                    self.isUpdatingPumpState = false

                    if let _ = error {
                        self.commandFailure = .resume
                    }
                }
            }
        } else {
            pumpManager.suspendDelivery { error in
                DispatchQueue.main.async {
                    self.isUpdatingPumpState = false

                    if let _ = error {
                        self.commandFailure = .suspend
                    }
                }
            }
        }
    }

    func switchAlgorithmToControlIQ() {
        isUpdatingPumpState = true

        let request = ChangeControlIQSettingsRequest(
            enabled: true,
            weightLbs: pumpManager?.state.controlIQWeight ?? 30,
            totalDailyInsulinUnits: pumpManager?.state.controlIQTotalDailyInsulin ?? 30
        )
        pumpManager?.configureControlIQMode(request) { success, cgmResponse in
            if success {
                let cgmActive = cgmResponse?.sessionState == .active

                DispatchQueue.main.async {
                    self.isUpdatingPumpState = false
                    self.useControlIQ = true
                    self.isCGMActiveOnPump = cgmActive
                    if !cgmActive {
                        self.showNoCGMWarning = true
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.isUpdatingPumpState = false
                    self.commandFailure = .controlIQ
                }
            }
        }
    }

    func switchAlgorithmToDIY() {
        isUpdatingPumpState = true

        let request = ChangeControlIQSettingsRequest(
            enabled: false,
            weightLbs: pumpManager?.state.controlIQWeight ?? 30,
            totalDailyInsulinUnits: pumpManager?.state.controlIQTotalDailyInsulin ?? 30
        )
        pumpManager?.configureControlIQMode(request) { success, _ in
            DispatchQueue.main.async {
                self.isUpdatingPumpState = false
                if success {
                    self.useControlIQ = false
                    self.showReenableClosedLoopPrompt = true
                } else {
                    self.commandFailure = .controlIQ
                }
            }
        }
    }

    func toggleExerciseMode() {
        isUpdatingPumpState = true

        let isExerciseOn = controlIQUserMode?.rawValue == 3
        pumpManager?.setControlIQMode(mode: isExerciseOn ? .exerciseModeOff : .exerciseModeOn) { success in
            guard success else {
                DispatchQueue.main.async {
                    self.isUpdatingPumpState = false
                    self.commandFailure = .exerciseMode
                }
                return
            }

            Thread.sleep(forTimeInterval: 1.0)
            self.pumpManager?.syncPumpData { _ in
                DispatchQueue.main.async {
                    self.isUpdatingPumpState = false
                }
            }
        }
    }

    func toggleSleepMode() {
        isUpdatingPumpState = true

        let isSleepOn = controlIQUserMode?.rawValue == 2
        pumpManager?.setControlIQMode(mode: isSleepOn ? .sleepModeOff : .sleepModeOn) { success in
            guard success else {
                DispatchQueue.main.async {
                    self.isUpdatingPumpState = false
                    self.commandFailure = .sleepMode
                }
                return
            }

            Thread.sleep(forTimeInterval: 1.0)
            self.pumpManager?.syncPumpData { _ in
                DispatchQueue.main.async {
                    self.isUpdatingPumpState = false
                }
            }
        }
    }

    func stopTempRate() {
        isUpdatingPumpState = true

        pumpManager?.enactTempBasal(unitsPerHour: 0, for: 0) { error in
            if error != nil {
                DispatchQueue.main.async {
                    self.isUpdatingPumpState = false
                    self.commandFailure = .stopTempRate
                }
                return
            }
            Thread.sleep(forTimeInterval: 1.0)
            self.pumpManager?.syncPumpData { _ in
                DispatchQueue.main.async {
                    self.isUpdatingPumpState = false
                }
            }
        }
    }

    func syncPumpTime() {
        guard let pumpManager = pumpManager else {
            return
        }

        isUpdatingTime = true
        pumpManager.syncPumpTime { _ in
            DispatchQueue.main.async {
                self.isUpdatingTime = false
            }
        }
    }

    func getLogs() -> [URL] {
        log.getDebugLogs()
    }

    func setAutoAcknowledgeBasalAlerts(_ enabled: Bool) {
        pumpManager?.configureAutoAcknowledgeBasalAlerts(enabled)
        autoAcknowledgeBasalAlerts = enabled
    }

    func setSilentMode(_ enabled: Bool) {
        pumpManager?.configureSilentMode(enabled)
        useSilentMode = enabled
    }

    func playSound() {
        isPlayingSound = true

        pumpManager?.playSound {
            DispatchQueue.main.async {
                self.isPlayingSound = false
            }
        }
    }

    func removePump() {
        pumpManager?.notifyDelegateOfDeactivation {
            DispatchQueue.main.async {
                self.nextStep()
            }
        }
    }

    deinit {
        pumpManager?.removeStatusObserver(self)
    }
}

extension TandemKitSettingsViewModel: PumpManagerStatusObserver {
    func pumpManager(
        _: any LoopKit.PumpManager,
        didUpdate _: LoopKit.PumpManagerStatus,
        oldStatus _: LoopKit.PumpManagerStatus
    ) {
        guard let pumpManager else {
            return
        }

        DispatchQueue.main.async {
            self.isConnected = pumpManager.state.isConnected
            self.reservoirValue = pumpManager.reservoirLevel
            self.showPumpTimeSyncWarning = pumpManager.state.showPumpTimeSyncWarning
            self.useControlIQ = pumpManager.state.useControlIQ
            self.scheduledBasal = pumpManager.getScheduledBasalRate()
            self.pumpState = pumpManager.state.pumpState
            self.controlIQEnabled = pumpManager.state.controlIQEnabled ?? false
            self.isClosedLoopEnabled = pumpManager.pumpManagerDelegate?.automaticDosingEnabled ?? false
            self.controlIQUserMode = pumpManager.state.controlIQUserMode
            self.currentProfileBaseBasalRate = pumpManager.getScheduledBasalRate()
            self.notificationCount = pumpManager.state.notificationCount ?? 0
            self.quickBolusEnabled = pumpManager.state.quickBolusEnabled
            self.algorithmModeText = self.useControlIQ ? "CIQ" : self.algorithmName
            self.basalDose = pumpManager.state.basalDose

            if pumpManager.state.basalDose.type == .suspend {
                self.suspendResumeText = String(localized: "Resume Insulin Delivery", comment: "resume delivery")
            } else {
                self.suspendResumeText = String(localized: "Suspend Insulin Delivery", comment: "suspend delivery")
            }

            if let battery = pumpManager.state.lastBatteryReading?.chargeRemaining {
                self.batteryPercentage = self.numberFormatter.string(from: (battery * 100) as NSNumber)
            }

            if let lastPumpTimeCheckDate = pumpManager.state.lastPumpTimeCheckDate {
                self.pumpTimeCheckedAt = self.dateFormatter.string(from: lastPumpTimeCheckDate)
            }

            if let currentPumpTime = pumpManager.state.currentPumpTime {
                self.currentPumpTime = self.dateFormatter.string(from: currentPumpTime)
            }

            if let reservoirLevel = pumpManager.reservoirLevel {
                self.reservoirUnitsText = String(format: "%.0f", reservoirLevel.unitVolume)
            }

            if let rate = self.currentProfileBaseBasalRate {
                self.currentBasalRateForDisplay = String(format: "%.2f", rate)
            }

            if self.controlIQUserMode?.rawValue == 2 {
                self.sleepModeText = String(localized: "Disable sleep mode", comment: "")
            } else {
                self.sleepModeText = String(localized: "Enable sleep mode", comment: "")
            }

            if self.controlIQUserMode?.rawValue == 3 {
                self.exerciseModeText = String(localized: "Disable exercise mode", comment: "")
            } else {
                self.exerciseModeText = String(localized: "Enable exercise mode", comment: "")
            }

            if self.controlIQEnabled {
                self.controlIqModeText = String(localized: "Disable ControlIQ", comment: "")
            } else {
                self.controlIqModeText = String(localized: "Enable ControlIQ", comment: "")
            }
        }
    }
}
