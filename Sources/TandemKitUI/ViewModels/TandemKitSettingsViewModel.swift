import CoreBluetooth
import LoopKit
import SwiftUI
import TandemCore

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
    var openInsulinType: () -> Void
    var openSoundSettings: () -> Void

    @Published var reservoirValue: ReservoirValue?
    @Published var isUpdatingPumpState = false
    @Published var showPumpTimeSyncWarning = false
    @Published var isUpdatingTime = false
    @Published var showingTimeSyncConfirmation = false
    @Published var commandFailure: CommandFailure?
    @Published var showingDeleteConfirmation = false
    @Published var showingDebugDetails = false
    @Published var autoAcknowledgeBasalAlerts: Bool = false
    @Published var useSilentMode: Bool = false
    @Published var alertSnoozeEnabled: Bool = false
    @Published var alertSnoozeDurationMins: Int = 10
    @Published var isPlayingSound: Bool = false

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
        openInsulinType: @escaping () -> Void,
        openSoundSettings: @escaping () -> Void
    ) {
        self.pumpManager = pumpManager
        self.nextStep = nextStep
        self.openInsulinType = openInsulinType
        self.openSoundSettings = openSoundSettings
        autoAcknowledgeBasalAlerts = pumpManager?.autoAcknowledgeBasalAlerts ?? false
        useSilentMode = pumpManager?.state.useSilentTones ?? false
        reservoirValue = pumpManager?.reservoirLevel
        showPumpTimeSyncWarning = pumpManager?.state.showPumpTimeSyncWarning ?? false

        self.pumpManager?.addStatusObserver(self, queue: .main)
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

    var pumpComm: PumpComm? {
        pumpManager?.tandemPump.pumpComm
    }

    // MARK: - Computed Properties from Manager State

    var controlIQEnabled: Bool {
        pumpManager?.state.controlIQEnabled ?? false
    }

    var controlIQUserMode: TandemPumpManagerState.ControlIQUserMode? {
        pumpManager?.state.controlIQUserMode
    }

    var tempRateActive: Bool {
        pumpManager?.state.tempRateAbsolute != nil
    }

    var tempRateAbsolute: Double? {
        pumpManager?.state.tempRateAbsolute
    }

    var tempRatePercentage: Int? {
        pumpManager?.state.tempRatePercentage
    }

    var tempRateDuration: Double? {
        pumpManager?.state.tempRateDuration
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

    var isSuspended: Bool? {
        guard let icon = pumpManager?.state.basalStatusIcon else { return nil }
        return icon == .suspended
    }

    // MARK: - Refresh Methods

    func refreshPumpStatus() {
        guard pumpManager?.connectedAndPaired == true else {
            log.debug("Skipping TandemPumpSettings refresh – pump not connected/paired")
            pendingRefreshOnReconnect = true
            return
        }

        pendingRefreshOnReconnect = false
        pumpManager?.ensureCurrentPumpData { _ in }
    }

    var reservoirUnitsText: String? {
        guard let reservoirValue else { return nil }
        return String(format: "%.1f", reservoirValue.unitVolume)
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
            guard let isSuspended = self.isSuspended else {
                DispatchQueue.main.async {
                    self.isUpdatingPumpState = false
                }
                return
            }

            if isSuspended {
                let response = self.pumpManager?.sendMessage(message: ResumePumpingRequest()) as? ResumePumpingResponse

                guard response?.isStatusOK == true else {
                    DispatchQueue.main.async {
                        self.isUpdatingPumpState = false
                        self.commandFailure = .resume
                    }
                    return
                }
            } else {
                let response = self.pumpManager?.sendMessage(message: SuspendPumpingRequest()) as? SuspendPumpingResponse

                guard response?.isStatusOK == true else {
                    DispatchQueue.main.async {
                        self.isUpdatingPumpState = false
                        self.commandFailure = .suspend
                    }
                    return
                }
            }

            self.pumpManager?.ensureCurrentPumpData { _ in }

            DispatchQueue.main.async {
                self.isUpdatingPumpState = false
            }
        }
    }

    func toggleControlIQMode() {
        // TODO(jwoglom): this should enforce that Trio closed loop is FULLY turned off
        isUpdatingPumpState = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    self?.isUpdatingPumpState = false
                }
                return
            }

            let isPumpControlIqOn = self.controlIQEnabled
            let weight = self.pumpManager?.state.controlIQWeight ?? 70
            let tdi = self.pumpManager?.state.controlIQTotalDailyInsulin ?? 30

            let response = self.pumpManager?.sendMessage(message: ChangeControlIQSettingsRequest(
                enabled: !isPumpControlIqOn,
                weightLbs: weight,
                totalDailyInsulinUnits: tdi
            )) as? ChangeControlIQSettingsResponse

            guard response?.isStatusOK == true else {
                DispatchQueue.main.async {
                    self.isUpdatingPumpState = false
                    self.commandFailure = .controlIQ
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

    func toggleExerciseMode() {
        isUpdatingPumpState = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    self?.isUpdatingPumpState = false
                }
                return
            }

            let isExerciseOn = self.controlIQUserMode?.rawValue == 3
            let command: SetModesRequest.ModeCommand = isExerciseOn ? .exerciseModeOff : .exerciseModeOn
            let response = self.pumpManager?.sendMessage(message: SetModesRequest(command: command)) as? SetModesResponse

            guard response?.isStatusOK == true else {
                DispatchQueue.main.async {
                    self.isUpdatingPumpState = false
                    self.commandFailure = .exerciseMode
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

    func toggleSleepMode() {
        isUpdatingPumpState = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    self?.isUpdatingPumpState = false
                }
                return
            }

            let isSleepOn = self.controlIQUserMode?.rawValue == 2
            let command: SetModesRequest.ModeCommand = isSleepOn ? .sleepModeOff : .sleepModeOn
            let response = self.pumpManager?.sendMessage(message: SetModesRequest(command: command)) as? SetModesResponse

            guard response?.isStatusOK == true else {
                DispatchQueue.main.async {
                    self.isUpdatingPumpState = false
                    self.commandFailure = .sleepMode
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

    func stopTempRate() {
        isUpdatingPumpState = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    self?.isUpdatingPumpState = false
                }
                return
            }

            self.pumpManager?.enactTempBasal(unitsPerHour: 0, for: 0) { error in
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
        TandemLogger.getDebugLogs()
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
        if isSuspended == true {
            return "Resume insulin delivery"
        } else if isSuspended == false {
            return "Suspend insulin delivery"
        }
        return nil
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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.pumpManager?.playSound()
            DispatchQueue.main.async {
                self?.isPlayingSound = false
            }
        }
    }

    // MARK: - Alert Snooze

    func setAlertSnooze(enabled: Bool, durationMins: Int) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.pumpManager?.setAlertSnooze(enabled: enabled, durationMins: durationMins)
            DispatchQueue.main.async {
                self?.alertSnoozeEnabled = enabled
                self?.alertSnoozeDurationMins = durationMins
            }
        }
    }

    // MARK: - Delivery Limits

    var maxBasalRateText: String? {
        guard let milliunits = pumpManager?.state.maxBasalLimitMilliunits else { return nil }
        return String(format: "%.2f U/hr", Double(milliunits) / 1000.0)
    }

    var maxBolusText: String? {
        guard let milliunits = pumpManager?.state.maxBolusLimitMilliunits else { return nil }
        return String(format: "%.1f U", Double(milliunits) / 1000.0)
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

    // MARK: - Factory Methods

    func createQuickBolusSettingsViewModel() -> TandemKitQuickBolusSettingsViewModel {
        TandemKitQuickBolusSettingsViewModel(pumpManager: pumpManager)
    }

    func createDeliveryLimitsViewModel() -> TandemKitDeliveryLimitsViewModel {
        TandemKitDeliveryLimitsViewModel(pumpManager: pumpManager)
    }

    // Cartridge operations
    func createChangeCartridgeViewModel() -> TandemKitChangeCartridgeViewModel {
        TandemKitChangeCartridgeViewModel(pumpManager: pumpManager)
    }

    func createFillTubingViewModel() -> TandemKitFillTubingViewModel {
        TandemKitFillTubingViewModel(pumpManager: pumpManager)
    }

    func createFillCannulaViewModel() -> TandemKitFillCannulaViewModel {
        TandemKitFillCannulaViewModel(pumpManager: pumpManager)
    }

    func createNotificationsViewModel() -> TandemKitNotificationsViewModel {
        TandemKitNotificationsViewModel(pumpManager)
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
        _ loopkitPumpManager: any LoopKit.PumpManager,
        didUpdate _: LoopKit.PumpManagerStatus,
        oldStatus _: LoopKit.PumpManagerStatus
    ) {
        guard let pumpManager = loopkitPumpManager as? TandemPumpManager else {
            return
        }

        DispatchQueue.main.async {
            self.reservoirValue = pumpManager.reservoirLevel
            self.showPumpTimeSyncWarning = pumpManager.state.showPumpTimeSyncWarning

            if self.pendingRefreshOnReconnect, pumpManager.connectedAndPaired {
                self.pendingRefreshOnReconnect = false
                self.refreshPumpStatus()
            }
        }
    }
}
