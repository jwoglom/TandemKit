import CoreBluetooth
import LoopKit
import SwiftUI
import TandemCore

class TandemKitSettingsViewModel: ObservableObject {
    private let log = PumpLogger(label: "TandemKitSettingsViewModel")
    private var pumpManager: TandemPumpManager?
    private var nextStep: () -> Void

    @Published var mirrorDetail: HomeScreenMirrorResponse?
    @Published var timeSinceReset: TimeSinceResetResponse?
    @Published var controlIQInfo: ControlIQInfoV2Response?
    @Published var insulinStatus: InsulinStatusResponse?
    @Published var tempRateStatus: TempRateResponse?
    @Published var currentBasalStatus: CurrentBasalStatusResponse?
    @Published var isUpdatingPumpState = false
    @Published var isSuspended: Bool? = nil
    @Published var showingDeleteConfirmation = false
    @Published var showingDebugDetails = false
    @Published var notificationCount: Int = 0

    private let notificationBundle = NotificationBundle()

    init(_ pumpManager: TandemPumpManager? = nil, nextStep: @escaping () -> Void) {
        self.pumpManager = pumpManager
        self.nextStep = nextStep

        self.pumpManager?.addStatusObserver(self, queue: .main)
        refreshPumpStatus()
    }

    var pumpState: PumpState? {
        pumpManager?.tandemPump.state
    }

    var pumpComm: PumpComm? {
        pumpManager?.tandemPump.pumpComm
    }

    func sendMessage(message: Message) -> Message? {
        guard let transport = pumpManager?.pairedTransport else {
            return nil
        }

        return try? transport.sendMessage(message)
    }

    func refreshPumpStatus() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let mirror = self.sendMessage(message: HomeScreenMirrorRequest()) as? HomeScreenMirrorResponse
            let controlIQ = self.sendMessage(message: ControlIQInfoV2Request()) as? ControlIQInfoV2Response
            let insulin = self.sendMessage(message: InsulinStatusRequest()) as? InsulinStatusResponse
            let tempRate = self.sendMessage(message: TempRateRequest()) as? TempRateResponse
            let currentBasal = self.sendMessage(message: CurrentBasalStatusRequest()) as? CurrentBasalStatusResponse

            // Refresh notification count
            for request in NotificationBundle.allRequests() {
                if let response = self.sendMessage(message: request) {
                    if NotificationBundle.isNotificationResponse(response) {
                        self.notificationBundle.add(response)
                    }
                }
            }
            let notifCount = self.notificationBundle.getNotificationCount()

            DispatchQueue.main.async {
                self.mirrorDetail = mirror
                self.controlIQInfo = controlIQ
                self.insulinStatus = insulin
                self.tempRateStatus = tempRate
                self.currentBasalStatus = currentBasal
                if let mirror = mirror {
                    self.isSuspended = mirror.basalStatusIconId == HomeScreenMirrorResponse.BasalStatusIcon.suspend.rawValue
                } else {
                    self.isSuspended = nil
                }
                self.notificationCount = notifCount
            }
        }
    }

    func refreshNotificationCount() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Refresh notification count
            for request in NotificationBundle.allRequests() {
                if let response = self.sendMessage(message: request) {
                    if NotificationBundle.isNotificationResponse(response) {
                        self.notificationBundle.add(response)
                    }
                }
            }
            let notifCount = self.notificationBundle.getNotificationCount()

            DispatchQueue.main.async {
                self.notificationCount = notifCount
            }
        }
    }

    func suspendResumeButtonPressed() {
        isUpdatingPumpState = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let isSuspended = self.isSuspended else { return }

            if isSuspended {
                _ = self.sendMessage(message: ResumePumpingRequest())
            } else {
                _ = self.sendMessage(message: SuspendPumpingRequest())
            }

            // Wait a moment for the pump to process
            Thread.sleep(forTimeInterval: 1.0)

            self.refreshPumpStatus()

            DispatchQueue.main.async {
                self.isUpdatingPumpState = false
            }
        }
    }

    func toggleExerciseMode() {
        isUpdatingPumpState = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let isExerciseOn = self.controlIQInfo?.currentUserModeTypeRaw == 3
            let command: SetModesRequest.ModeCommand = isExerciseOn ? .exerciseModeOff : .exerciseModeOn
            _ = self.sendMessage(message: SetModesRequest(command: command))

            Thread.sleep(forTimeInterval: 1.0)
            self.refreshPumpStatus()

            DispatchQueue.main.async {
                self.isUpdatingPumpState = false
            }
        }
    }

    func toggleSleepMode() {
        isUpdatingPumpState = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let isSleepOn = self.controlIQInfo?.currentUserModeTypeRaw == 2
            let command: SetModesRequest.ModeCommand = isSleepOn ? .sleepModeOff : .sleepModeOn
            _ = self.sendMessage(message: SetModesRequest(command: command))

            Thread.sleep(forTimeInterval: 1.0)
            self.refreshPumpStatus()

            DispatchQueue.main.async {
                self.isUpdatingPumpState = false
            }
        }
    }

    func stopTempRate() {
        isUpdatingPumpState = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            _ = self.sendMessage(message: StopTempRateRequest())

            Thread.sleep(forTimeInterval: 1.0)
            self.refreshPumpStatus()

            DispatchQueue.main.async {
                self.isUpdatingPumpState = false
            }
        }
    }

    var suspendResumeText: String? {
        if isSuspended == true {
            return "Resume insulin delivery"
        } else if isSuspended == false {
            return "Suspend insulin delivery"
        }
        return nil
    }

    var exerciseModeText: String {
        if let mode = controlIQInfo?.currentUserModeTypeRaw, mode == ControlIQInfoV2Response.UserModeType.exercise.rawValue {
            return "Disable exercise mode"
        }
        return "Enable exercise mode"
    }

    var sleepModeText: String {
        if let mode = controlIQInfo?.currentUserModeTypeRaw, mode == ControlIQInfoV2Response.UserModeType.sleep.rawValue {
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
    }
}
