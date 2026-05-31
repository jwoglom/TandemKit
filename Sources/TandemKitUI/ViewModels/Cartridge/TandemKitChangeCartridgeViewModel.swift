import Combine
import LoopKit
import SwiftUI

enum CartridgeChangeStep: Int {
    case suspend = 0
    case enterMode = 1
    case waitingForReady = 2
    case physicalChange = 3
    case detecting = 4
    case done = 5

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

    let done: () -> Void
    let toFillTubing: () -> Void
    private let pumpManager: TandemPumpManager?
    private let processQueue = DispatchQueue(label: "TandemKit.cartridge.processQueue")

    // Notifications
    @Published var notificationsViewModel: TandemKitNotificationsViewModel
    private var notificationCheckTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    var hasActiveNotifications: Bool {
        !notificationsViewModel.notifications.isEmpty
    }

    init(pumpManager: TandemPumpManager?, done: @escaping () -> Void, toFillTubing: @escaping () -> Void) {
        self.pumpManager = pumpManager
        self.done = done
        self.toFillTubing = toFillTubing
        notificationsViewModel = TandemKitNotificationsViewModel(pumpManager)

        // Forward child ViewModel changes to parent
        notificationsViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    deinit {
        notificationCheckTask?.cancel()
    }

    func startPeriodicNotificationCheck() async {
        // Cancel any existing task
        notificationCheckTask?.cancel()

        // Create a new task that checks every 15 seconds
        notificationCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }

                // Refresh notifications
                await MainActor.run {
                    self.notificationsViewModel.refreshNotifications()
                }

                // Wait 15 seconds before next check
                do {
                    try await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
                } catch {
                    // Task was cancelled
                    break
                }
            }
        }
    }

    func stopPeriodicNotificationCheck() {
        notificationCheckTask?.cancel()
        notificationCheckTask = nil
    }

    func checkSuspendedStatus() {
        pumpManager?.fetchSuspendStatus { isSuspended in
            DispatchQueue.main.async {
                self.isSuspended = isSuspended

                if self.isSuspended == true, self.currentStep == .suspend {
                    self.currentStep = .enterMode
                }
            }
        }
    }

    func suspendPumping() {
        loadingSuspend = true
        failedSuspend = false

        pumpManager?.suspendDelivery { error in
            DispatchQueue.main.async {
                self.loadingSuspend = false
                if let _ = error {
                    self.failedSuspend = true

                } else {
                    self.failedSuspend = false
                    self.isSuspended = true
                    self.currentStep = self.currentStep.nextStep() ?? .done
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

        pumpManager?.enterChangeCartridgeMode { response in
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
        failedExitMode = false

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
                    // Exit change cartridge mode before completing
                    self.exitChangeCartridgeMode()
                }
            }
        }
    }

    func retryExitCartridgeMode() {
        failedExitMode = false
        exitChangeCartridgeMode()
    }

    func exitChangeCartridgeMode() {
        loadingExitMode = true
        failedExitMode = false

        pumpManager?.exitChangeCartridgeMode { response in
            DispatchQueue.main.async {
                self.loadingExitMode = false
                self.isProcessing = false

                if let response = response, response.status == 0 {
                    self.failedExitMode = false
                    self.currentStep = self.currentStep.nextStep() ?? .done
                } else {
                    // Exit failed - go back to detecting step and show error
                    self.failedExitMode = true
                    self.currentStep = .detecting
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
