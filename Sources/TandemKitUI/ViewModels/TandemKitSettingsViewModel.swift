import CoreBluetooth
import LoopKit
import SwiftUI
import TandemCore

class TandemKitSettingsViewModel: ObservableObject {
    private let log = TandemLogger(category: "TandemKitSettingsViewModel")
    private var pumpManager: TandemPumpManager?
    private var nextStep: () -> Void
    var openInsulinType: () -> Void
    var openSoundSettings: () -> Void

    @Published var reservoirValue: ReservoirValue?
    @Published var isUpdatingPumpState = false
    @Published var showingDeleteConfirmation = false
    @Published var showingDebugDetails = false
    @Published var autoAcknowledgeBasalAlerts: Bool = false
    @Published var useSilentMode: Bool = false

    private var pendingRefreshOnReconnect = false

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

        self.pumpManager?.addStatusObserver(self, queue: .main)
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
        pumpManager?.state.tempRateActive ?? false
    }

    var tempRatePercentage: Int? {
        pumpManager?.state.tempRatePercentage
    }

    var tempRateDuration: UInt32? {
        pumpManager?.state.tempRateDuration
    }

    var currentBasalRate: Double? {
        pumpManager?.state.currentBasalRate
    }

    var currentBasalRateForDisplay: String {
        guard let rate = currentBasalRate else { return "" }
        return String(format: "%.2f U/hr", rate)
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
                _ = self.pumpManager?.sendMessage(message: ResumePumpingRequest())
            } else {
                _ = self.pumpManager?.sendMessage(message: SuspendPumpingRequest())
            }

            // Wait a moment for the pump to process
            Thread.sleep(forTimeInterval: 1.0)

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

            _ = self.pumpManager?.sendMessage(message: ChangeControlIQSettingsRequest(
                enabled: !isPumpControlIqOn,
                weightLbs: weight,
                totalDailyInsulinUnits: tdi
            ))

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
            _ = self.pumpManager?.sendMessage(message: SetModesRequest(command: command))

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
            _ = self.pumpManager?.sendMessage(message: SetModesRequest(command: command))

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

            self.pumpManager?.enactTempBasal(unitsPerHour: 0, for: 0) { _ in
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

    func getLogs() -> [URL] {
        TandemLogger.getDebugLogs()
    }

    func setAutoAcknowledgeBasalAlerts(_ enabled: Bool) {
        pumpManager?.configureAutoAcknowledgeBasalAlerts(enabled)
        autoAcknowledgeBasalAlerts = enabled
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

    func createCGMSettingsViewModel() -> TandemKitCGMSettingsViewModel {
        TandemKitCGMSettingsViewModel(pumpManager: pumpManager)
    }

    func createDebugViewModel() -> TandemKitDebugViewModel {
        TandemKitDebugViewModel(pumpManager: pumpManager)
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

        reservoirValue = pumpManager.reservoirLevel

        if pendingRefreshOnReconnect, pumpManager.connectedAndPaired {
            pendingRefreshOnReconnect = false
            refreshPumpStatus()
        }

        // Force SwiftUI to re-evaluate computed properties
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
}
