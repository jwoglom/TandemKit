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
    let openDebug: () -> Void
    let openTroubleshootConnection: () -> Void
    let allowDebugFeatures: Bool

    var appName: String { HostApp.current.appName }
    var algorithmName: String { HostApp.current.diyAlgorithmName }

    @Published var pumpState: PumpState? = nil
    @Published var controlIQEnabled: Bool = false
    @Published var isClosedLoopEnabled: Bool = false
    @Published var currentProfileBaseBasalRate: Double? = nil
    @Published var currentBasalRateForDisplay: String = ""
    @Published var batteryPercentage: String? = nil
    /// Remaining charge as a 0...1 fraction, used to draw the battery indicator.
    @Published var batteryChargeRemaining: Double? = nil
    @Published var batteryIsCharging: Bool = false
    @Published var pumpTimeCheckedAt: String = ""
    @Published var currentPumpTime: String = ""
    @Published var reservoirUnitsText: String? = nil
    @Published var controlIQUserMode: TandemPumpManagerState.ControlIQUserMode? = nil
    @Published var reservoirValue: ReservoirValue?
    @Published var cannulaAge: String? = nil
    @Published var insulinAge: String? = nil
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
    /// Why the pump cannot be reached, or nil when it can. Drives the banner at the top.
    @Published var connectionIssue: PumpConnectionIssue?
    @Published var isRefreshing: Bool = false
    @Published var isPlayingSound: Bool = false
    @Published var useControlIQ: Bool = false
    @Published var showReenableClosedLoopPrompt: Bool = false
    @Published var showNoCGMWarning: Bool = false
    /// Whether a CGM sensor session is established on the pump, or nil while that is unknown (the
    /// pump has not been read yet, or the read failed). Unknown is deliberately distinct from
    /// `false`: only a confirmed absence should raise the "no CGM connected" warning.
    @Published var isCGMActiveOnPump: Bool?
    @Published var pendingEnableClosedLoop: Bool = false
    @Published var showCGMRequiredForCIQ: Bool = false
    @Published var showControlIQValuesRequired: Bool = false
    @Published var showSwitchToCIQConfirm: Bool = false
    @Published var isCheckingCGMForCIQ: Bool = false
    /// Gates the Control-IQ settings screen and the switch *to* Control-IQ. Switching back to the
    /// DIY algorithm is never gated, so a pump already running Control-IQ stays recoverable.
    @Published var controlIQSupportEnabled: Bool = false
    @Published var quickBolusButtonSupportEnabled: Bool = false

    /// Whether to warn that Control-IQ is running open-loop for want of a CGM. Only a pump we know
    /// has no sensor session earns the warning; an unknown session state does not.
    var showsNoCGMConnectedBanner: Bool {
        useControlIQ && isCGMActiveOnPump == false
    }

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
        openAlertSettings: @escaping () -> Void,
        openDebug: @escaping () -> Void = {},
        openTroubleshootConnection: @escaping () -> Void = {},
        allowDebugFeatures: Bool = false
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
        self.openDebug = openDebug
        self.openTroubleshootConnection = openTroubleshootConnection
        self.allowDebugFeatures = allowDebugFeatures
        useControlIQ = pumpManager?.state.useControlIQ ?? false
        controlIQSupportEnabled = pumpManager?.state.featureFlags.controlIQSupport ?? false
        quickBolusButtonSupportEnabled = pumpManager?.state.featureFlags.quickBolusButtonSupport ?? false
        isCGMActiveOnPump = pumpManager?.state.isCGMSensorSessionConfigured
        reservoirValue = pumpManager?.reservoirLevel
        connectionIssue = pumpManager?.connectionIssue
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

    /// Whether the pump is currently suspended, used to decide which confirmation to present and
    /// which command to issue.
    var isDeliverySuspended: Bool {
        basalDose?.type == .suspend
    }

    func suspendResumeButtonPressed() {
        guard let pumpManager else {
            return
        }

        isUpdatingPumpState = true

        let wasSuspended = pumpManager.state.basalDose.type == .suspend
        let failure: CommandFailure = wasSuspended ? .resume : .suspend

        // Shared completion: surface the error sheet on failure, otherwise re-sync the pump so the
        // delivery status and suspend/resume button reflect the pump's actual state instead of
        // leaving the UI ambiguous about whether the command took effect. The brief sleep lets the
        // pump settle before we read the reconciled state back, matching the other therapy commands.
        let handleCompletion: (Error?) -> Void = { error in
            if error != nil {
                DispatchQueue.main.async {
                    self.isUpdatingPumpState = false
                    self.commandFailure = failure
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

        if wasSuspended {
            // Resuming clears the pump's "insulin isn't being delivered" alarms on the user's
            // behalf and retries once before failing, so the error sheet is only shown when the
            // resume genuinely could not be completed.
            pumpManager.resumeDeliveryAcknowledgingResumeAlarms(completion: handleCompletion)
        } else {
            pumpManager.suspendDelivery(completion: handleCompletion)
        }
    }

    /// Begins a switch of the pump algorithm to Control-IQ.
    ///
    /// Control-IQ can only close the loop when a CGM is connected to the pump; without one the
    /// pump silently runs Control-IQ in open-loop while our DIY algorithm is disabled — a strictly
    /// worse state for the user. To prevent that, first confirm a CGM sensor session is configured
    /// on the pump. Only when one is present do we surface the switch confirmation; otherwise we
    /// show a blocking prompt directing the user to connect a CGM and leave the algorithm unchanged.
    func attemptSwitchToControlIQ() {
        guard let pumpManager else { return }
        guard !isCheckingCGMForCIQ else { return }

        guard pumpManager.state.featureFlags.controlIQSupport else {
            log.debug("Ignoring switch to Control-IQ: controlIQSupport feature flag is off")
            return
        }

        // Control-IQ doses from body weight and total daily insulin, and a pump that has never run
        // it has neither, so the driver refuses the enable. Open the screen where they can be
        // entered instead of attempting a request that cannot succeed (#223).
        guard pumpManager.state.controlIQWeightLbs != nil,
              pumpManager.state.controlIQTotalDailyInsulin != nil
        else {
            showControlIQValuesRequired = true
            return
        }

        isCheckingCGMForCIQ = true
        pumpManager.getCGMStatus { response in
            DispatchQueue.main.async {
                self.isCheckingCGMForCIQ = false
                if response?.isSensorSessionConfigured == true {
                    self.showSwitchToCIQConfirm = true
                } else {
                    self.showCGMRequiredForCIQ = true
                }
            }
        }
    }

    func switchAlgorithmToControlIQ() {
        isUpdatingPumpState = true

        // Weight and TDI come from the pump, and are absent until Control-IQ has been configured
        // there at least once. Sending a placeholder in their place only earns a rejection, so pass
        // the absence through and let the driver refuse with an error that names what is missing.
        let request = ChangeControlIQSettingsRequest(
            enabled: true,
            weightLbs: pumpManager?.state.controlIQWeightLbs ?? 0,
            totalDailyInsulinUnits: pumpManager?.state.controlIQTotalDailyInsulin ?? 0
        )
        pumpManager?.configureControlIQMode(request) { result in
            switch result {
            case let .success(cgmResponse):
                // A sensor that is still warming up counts as connected — it will start feeding
                // Control-IQ shortly — matching the check that gated this switch in the first
                // place (`attemptSwitchToControlIQ`). A missing response leaves the session state
                // unknown, and an unknown state is not grounds for the warning.
                let cgmConfigured = cgmResponse?.isSensorSessionConfigured

                DispatchQueue.main.async {
                    self.isUpdatingPumpState = false
                    self.useControlIQ = true
                    self.isCGMActiveOnPump = cgmConfigured
                    if cgmConfigured == false {
                        self.showNoCGMWarning = true
                    }
                }
            case .failure:
                DispatchQueue.main.async {
                    self.isUpdatingPumpState = false
                    self.commandFailure = .controlIQ
                }
            }
        }
    }

    func switchAlgorithmToDIY() {
        isUpdatingPumpState = true

        // Turning Control-IQ off carries the same fields but does not depend on them, so an unset
        // weight/TDI is no obstacle here.
        let request = ChangeControlIQSettingsRequest(
            enabled: false,
            weightLbs: pumpManager?.state.controlIQWeightLbs ?? 0,
            totalDailyInsulinUnits: pumpManager?.state.controlIQTotalDailyInsulin ?? 0
        )
        pumpManager?.configureControlIQMode(request) { result in
            DispatchQueue.main.async {
                self.isUpdatingPumpState = false
                switch result {
                case .success:
                    self.useControlIQ = false
                    self.showReenableClosedLoopPrompt = true
                case .failure:
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

    func playSound() {
        isPlayingSound = true

        pumpManager?.playSound {
            DispatchQueue.main.async {
                self.isPlayingSound = false
            }
        }
    }

    func removePump() {
        // Advance the flow. The coordinator's stepFinished runs prepareForDeactivation, which tears
        // down the BLE transport (stopping auto-reconnect) and notifies the delegate — both required
        // for the pump to actually be removed rather than reconnect and re-persist its state.
        nextStep()
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
            self.connectionIssue = pumpManager.connectionIssue
            self.reservoirValue = pumpManager.reservoirLevel
            self.showPumpTimeSyncWarning = pumpManager.state.showPumpTimeSyncWarning
            self.useControlIQ = pumpManager.state.useControlIQ
            self.controlIQSupportEnabled = pumpManager.state.featureFlags.controlIQSupport
            self.quickBolusButtonSupportEnabled = pumpManager.state.featureFlags.quickBolusButtonSupport
            self.isCGMActiveOnPump = pumpManager.state.isCGMSensorSessionConfigured
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

            if let batteryReading = pumpManager.state.lastBatteryReading {
                let battery = batteryReading.chargeRemaining
                self.batteryPercentage = self.numberFormatter.string(from: (battery * 100) as NSNumber)
                self.batteryChargeRemaining = battery
                self.batteryIsCharging = batteryReading.isCharging
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

            if let lastSiteChangeDate = pumpManager.state.lastSiteChangeDate {
                self.cannulaAge = formatDurationToDaysHours(since: lastSiteChangeDate)
            } else {
                self.cannulaAge = nil
            }

            if let lastCartridgeChangeDate = pumpManager.state.lastCartridgeChangeDate {
                self.insulinAge = formatDurationToDaysHours(since: lastCartridgeChangeDate)
            } else {
                self.insulinAge = nil
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
