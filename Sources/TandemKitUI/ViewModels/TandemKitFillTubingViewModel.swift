import LoopKit
import SwiftUI
import TandemCore

enum TubingFillStep: Int {
    case suspend = 0
    case enterMode = 1
    case filling = 2
    case exiting = 3
    case done = 4

    func nextStep() -> TubingFillStep? {
        switch self {
        case .suspend:
            return .enterMode
        case .enterMode:
            return .filling
        case .filling:
            return .exiting
        case .exiting:
            return .done
        case .done:
            return nil
        }
    }
}

class TandemKitFillTubingViewModel: ObservableObject {
    @Published var currentStep: TubingFillStep = .suspend
    @Published var isSuspended: Bool? = nil
    @Published var isProcessing = false

    @Published var loadingSuspend = false
    @Published var loadingEnterMode = false
    @Published var loadingExitMode = false

    @Published var failedSuspend = false
    @Published var failedEnterMode = false
    @Published var failedExitMode = false

    @Published var buttonDown = false
    @Published var exitState: ExitFillTubingModeStateStreamResponse.ExitFillTubingModeState?

    @Published var showingSuspendConfirmation = false
    @Published var showingCancelConfirmation = false

    private let pumpManager: TandemPumpManager?
    private let processQueue = DispatchQueue(label: "TandemKit.tubing.processQueue")

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

    func enterFillTubingMode() {
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
                let response = try? transport.sendMessage(EnterFillTubingModeRequest()) as? EnterFillTubingModeResponse

                DispatchQueue.main.async {
                    self.loadingEnterMode = false
                    if let response = response, response.status == 0 {
                        self.failedEnterMode = false
                        self.currentStep = self.currentStep.nextStep() ?? .done
                        self.startMonitoringButtonState()
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

    func startMonitoringButtonState() {
        // Monitor for button press state
        // In a real implementation, this would subscribe to FillTubingStateStreamResponse
        // For now, simulate monitoring
    }

    func tubingFilled() {
        currentStep = currentStep.nextStep() ?? .done
        exitFillTubingMode()
    }

    func exitFillTubingMode() {
        loadingExitMode = true
        failedExitMode = false

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let transport = self.pumpManager?.pairedTransport {
                let response = try? transport.sendMessage(ExitFillTubingModeRequest()) as? ExitFillTubingModeResponse

                DispatchQueue.main.async {
                    self.loadingExitMode = false
                    self.isProcessing = false
                    if let response = response, response.status == 0 {
                        self.failedExitMode = false
                        self.exitState = .tubingFilled
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
        // Attempt to exit fill tubing mode if we're in it
        if currentStep.rawValue >= TubingFillStep.enterMode.rawValue,
           currentStep.rawValue < TubingFillStep.done.rawValue
        {
            exitFillTubingMode()
        }
    }
}
