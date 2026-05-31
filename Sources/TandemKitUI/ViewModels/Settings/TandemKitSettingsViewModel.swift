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

    @Published var reservoirValue: ReservoirValue?
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

    private var pendingRefreshOnReconnect = false

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

        self.pumpManager?.addStatusObserver(self, queue: .main)

        refreshPumpStatus()
    }

    var currentPumpTime: String {
        guard let currentPumpTime = pumpManager?.state.currentPumpTime else {
            return ""
        }

        return dateFormatter.string(from: currentPumpTime)
    }

    var pumpTimeCheckedAt: String {
        guard let lastPumpTimeCheckDate = pumpManager?.state.lastPumpTimeCheckDate else {
            return ""
        }

        return dateFormatter.string(from: lastPumpTimeCheckDate)
    }

    var pumpState: PumpState? {
        pumpManager?.state.pumpState
    }

    // MARK: - Computed Properties from Manager State

    var controlIQEnabled: Bool {
        pumpManager?.state.controlIQEnabled ?? false
    }

    var isClosedLoopEnabled: Bool {
        pumpManager?.pumpManagerDelegate?.automaticDosingEnabled ?? false
    }

    var controlIQUserMode: TandemPumpManagerState.ControlIQUserMode? {
        pumpManager?.state.controlIQUserMode
    }

    var batteryPercentage: String? {
        guard let battery = pumpManager?.state.lastBatteryReading?.chargeRemaining else {
            return nil
        }

        return numberFormatter.string(from: (battery * 100) as NSNumber)
    }

    var currentProfileBaseBasalRate: Double? {
        pumpManager?.getScheduledBasalRate()
    }

    var currentBasalRateForDisplay: String {
        guard let rate = currentProfileBaseBasalRate else { return "" }
        return String(format: "%.2f", rate)
    }

    var notificationCount: Int {
        pumpManager?.state.notificationCount ?? 0
    }

    // MARK: - Refresh Methods

    func refreshPumpStatus() {
        guard let pumpManager else {
            log.debug("Skipping TandemPumpSettings refresh – pump not connected/paired")
            pendingRefreshOnReconnect = true
            return
        }

        guard !isRefreshing else { return }

        pendingRefreshOnReconnect = false
        isRefreshing = true

        pumpManager.ensureCurrentPumpData { _ in
            DispatchQueue.main.async {
                self.isRefreshing = false
            }
        }
    }

    var reservoirUnitsText: String? {
        guard let reservoirValue else { return nil }
        return String(format: "%.0f", reservoirValue.unitVolume)
    }

    func suspendResumeButtonPressed() {
        isUpdatingPumpState = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    self?.isUpdatingPumpState = false
                }
                return
            }
            guard let dose = basalDose, let pumpManager = self.pumpManager else {
                DispatchQueue.main.async {
                    self.isUpdatingPumpState = false
                }
                return
            }

            if dose.type == .suspend {
                pumpManager.resumeDelivery { error in
                    if let _ = error {
                        DispatchQueue.main.async {
                            self.isUpdatingPumpState = false
                            self.commandFailure = .resume
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.isUpdatingPumpState = false
                        }
                    }
                }
            } else {
                pumpManager.suspendDelivery { error in
                    if let _ = error {
                        DispatchQueue.main.async {
                            self.isUpdatingPumpState = false
                            self.commandFailure = .suspend
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.isUpdatingPumpState = false
                        }
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
            self.pumpManager?.ensureCurrentPumpData { _ in
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
            self.pumpManager?.ensureCurrentPumpData { _ in
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
            self.pumpManager?.ensureCurrentPumpData { _ in }

            DispatchQueue.main.async {
                self.isUpdatingPumpState = false
            }
        }
    }

    func toggleSilentMode() {
        pumpManager?.configureSilentMode(!useSilentMode)
        useSilentMode = !useSilentMode
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

    var suspendResumeText: String? {
        guard let dose = basalDose else {
            return nil
        }

        if dose.type == .suspend {
            return String(localized: "Resume insulin delivery", comment: "resume delivery")
        }

        return String(localized: "Suspend insulin delivery", comment: "suspend delivery")
    }

    var appName: String { HostApp.current.appName }
    var algorithmName: String { HostApp.current.diyAlgorithmName }

    var algorithmModeText: String {
        useControlIQ ? "CIQ" : algorithmName
    }

    var controlIqModeText: String {
        if controlIQEnabled {
            return "Disable ControlIQ"
        }
        return "Enable ControlIQ"
    }

    var exerciseModeText: String {
        if controlIQUserMode?.rawValue == 3 {
            return "Disable exercise mode"
        }
        return "Enable exercise mode"
    }

    var sleepModeText: String {
        if controlIQUserMode?.rawValue == 2 {
            return "Disable sleep mode"
        }
        return "Enable sleep mode"
    }

    // MARK: - Find My Pump

    func playSound() {
        isPlayingSound = true

        pumpManager?.playSound {
            DispatchQueue.main.async {
                self.isPlayingSound = false
            }
        }
    }

    // MARK: - Quick Bolus

    var quickBolusEnabled: Bool? {
        pumpManager?.state.quickBolusEnabled
    }

    var quickBolusSummary: String? {
        guard let enabled = pumpManager?.state.quickBolusEnabled else { return nil }
        if !enabled { return "Disabled" }

        let entryType = pumpManager?.state.quickBolusEntryType ?? 0
        if entryType == 1 {
            let carbsMilliunits = pumpManager?.state.quickBolusIncrementCarbs ?? 0
            let carbs = Double(carbsMilliunits) / 1000.0
            return String(format: "Carbs, %.0f g", carbs)
        } else {
            let unitsMilliunits = pumpManager?.state.quickBolusIncrementUnits ?? 0
            let units = Double(unitsMilliunits) / 1000.0
            return String(format: "Units, %.1f U", units)
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
            self.isConnected = false
            self.reservoirValue = pumpManager.reservoirLevel
            self.showPumpTimeSyncWarning = pumpManager.state.showPumpTimeSyncWarning
            self.useControlIQ = pumpManager.state.useControlIQ
            self.scheduledBasal = pumpManager.getScheduledBasalRate()

            if self.pendingRefreshOnReconnect {
                self.pendingRefreshOnReconnect = false
                self.refreshPumpStatus()
            }
        }
    }
}
