import LoopKit
import SwiftUI
import TandemCore

enum CartridgeChangeStep: Int {
    case suspend = 0
    case enterMode = 1
    case waitingForReady = 2
    case physicalChange = 3
    case detecting = 4
    case completing = 5
    case done = 6

    func nextStep() -> CartridgeChangeStep? {
        switch self {
        case .suspend:
            return .enterMode
        case .enterMode:
            return .waitingForReady
        case .waitingForReady:
            return .physicalChange
        case .physicalChange:
            return .detecting
        case .detecting:
            return .completing
        case .completing:
            return .done
        case .done:
            return nil
        }
    }
}

class TandemKitChangeCartridgeViewModel: ObservableObject {
    @Published var currentStep: CartridgeChangeStep = .suspend
    @Published var isSuspended: Bool? = nil
    @Published var isProcessing = false

    @Published var loadingSuspend = false
    @Published var loadingEnterMode = false
    @Published var loadingExitMode = false

    @Published var failedSuspend = false
    @Published var failedEnterMode = false
    @Published var failedExitMode = false

    @Published var changeCartridgeState: EnterChangeCartridgeModeStateStreamResponse.ChangeCartridgeState?
    @Published var detectingProgress: Int = 0
    @Published var isDetecting = false

    @Published var showingSuspendConfirmation = false
    @Published var showingCancelConfirmation = false

    private let pumpManager: TandemPumpManager?
    private let processQueue = DispatchQueue(label: "TandemKit.cartridge.processQueue")

    init(pumpManager: TandemPumpManager?) {
        self.pumpManager = pumpManager
        checkSuspendedStatus()
    }

    func checkSuspendedStatus() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let transport = self.pumpManager?.pairedTransport {
                let mirror = try? transport.sendMessage(HomeScreenMirrorRequest()) as? HomeScreenMirrorResponse

                DispatchQueue.main.async {
                    self.isSuspended = mirror?.basalStatusIconId == HomeScreenMirrorResponse.BasalStatusIcon.suspend.rawValue
                    if self.isSuspended == true, self.currentStep == .suspend {
                        self.currentStep = .enterMode
                    }
                }
            }
        }
    }

    func suspendPumping() {
        loadingSuspend = true
        failedSuspend = false

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let transport = self.pumpManager?.pairedTransport {
                let response = try? transport.sendMessage(SuspendPumpingRequest())

                Thread.sleep(forTimeInterval: 1.0)
                self.checkSuspendedStatus()

                DispatchQueue.main.async {
                    self.loadingSuspend = false
                    if let _ = response {
                        self.failedSuspend = false
                        self.isSuspended = true
                        self.currentStep = self.currentStep.nextStep() ?? .done
                    } else {
                        self.failedSuspend = true
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.loadingSuspend = false
                    self.failedSuspend = true
                }
            }
        }
    }

    func enterChangeCartridgeMode() {
        guard isSuspended == true else {
            failedEnterMode = true
            return
        }

        loadingEnterMode = true
        failedEnterMode = false
        isProcessing = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let transport = self.pumpManager?.pairedTransport {
                let response = try? transport.sendMessage(EnterChangeCartridgeModeRequest()) as? EnterChangeCartridgeModeResponse

                DispatchQueue.main.async {
                    self.loadingEnterMode = false
                    if let response = response, response.status == 0 {
                        self.failedEnterMode = false
                        self.currentStep = self.currentStep.nextStep() ?? .done
                        self.startMonitoringChangeState()
                    } else {
                        self.failedEnterMode = true
                        self.isProcessing = false
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.loadingEnterMode = false
                    self.failedEnterMode = true
                    self.isProcessing = false
                }
            }
        }
    }

    func startMonitoringChangeState() {
        // Monitor for ready state
        // In a real implementation, this would subscribe to the control stream
        // For now, simulate state progression
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.changeCartridgeState = .readyToChange
            self?.currentStep = self?.currentStep.nextStep() ?? .done
        }
    }

    func cartridgeInserted() {
        currentStep = currentStep.nextStep() ?? .done
        startDetectingCartridge()
    }

    func startDetectingCartridge() {
        isDetecting = true
        detectingProgress = 0

        // Monitor detection progress
        // In a real implementation, this would subscribe to DetectingCartridgeStateStreamResponse
        // For now, simulate progress
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            DispatchQueue.main.async {
                self.detectingProgress += 10

                if self.detectingProgress >= 100 {
                    timer.invalidate()
                    self.isDetecting = false
                    self.currentStep = self.currentStep.nextStep() ?? .done
                }
            }
        }
    }

    func exitChangeCartridgeMode() {
        loadingExitMode = true
        failedExitMode = false

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let transport = self.pumpManager?.pairedTransport {
                let response = try? transport.sendMessage(ExitChangeCartridgeModeRequest()) as? ExitChangeCartridgeModeResponse

                DispatchQueue.main.async {
                    self.loadingExitMode = false
                    self.isProcessing = false
                    if let response = response, response.status == 0 {
                        self.failedExitMode = false
                        self.currentStep = self.currentStep.nextStep() ?? .done
                    } else {
                        self.failedExitMode = true
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.loadingExitMode = false
                    self.failedExitMode = true
                    self.isProcessing = false
                }
            }
        }
    }

    func cancelOperation() {
        // Attempt to exit change cartridge mode if we're in it
        if currentStep.rawValue >= CartridgeChangeStep.enterMode.rawValue,
           currentStep.rawValue < CartridgeChangeStep.done.rawValue
        {
            exitChangeCartridgeMode()
        }
    }
}
