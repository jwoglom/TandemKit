import Combine
import LoopKit
import SwiftUI

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
    @Published var loadingResume = false

    @Published var failedSuspend = false
    @Published var failedEnterMode = false
    @Published var failedExitMode = false
    @Published var failedResume = false

    @Published var buttonDown = false
    @Published var hasDisplayedFlow = false
    @Published var exitState: ExitFillTubingModeStateStreamResponse.ExitFillTubingModeState?

    let done: () -> Void
    let toFillingCannula: () -> Void
    private let pumpManager: TandemPumpManager?
    private let processQueue = DispatchQueue(label: "TandemKit.tubing.processQueue")

    // Notifications
    @Published var notificationsViewModel: TandemKitNotificationsViewModel
    private var notificationCheckTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    var hasActiveNotifications: Bool {
        !notificationsViewModel.notifications.isEmpty
    }

    init(pumpManager: TandemPumpManager?, done: @escaping () -> Void, toFillingCannula: @escaping () -> Void) {
        self.pumpManager = pumpManager
        self.done = done
        self.toFillingCannula = toFillingCannula
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
        // Subscribe to FillTubingStateStreamResponse from the pump manager
        guard let pumpManager = pumpManager else { return }

        pumpManager.fillTubingStateStream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] response in
                self?.buttonDown = response.buttonDown
                if response.buttonDown {
                    self?.hasDisplayedFlow = true
                } else {
                    self?.requestAlertStatus()
                }
            }
            .store(in: &cancellables)
    }

    private func requestAlertStatus() {
        processQueue.async { [weak self] in
            guard let transport = self?.pumpManager?.pairedTransport else { return }
            _ = try? transport.sendMessage(AlertStatusRequest()) as? AlertStatusResponse
        }
    }

    func tubingFilled() {
        // Advance to exiting step to show loading screen
        currentStep = currentStep.nextStep() ?? .done
        exitFillTubingMode()
    }

    func resumeDelivery() {
        loadingResume = true
        failedResume = false

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let pumpManager = self.pumpManager else { return }

            pumpManager.resumeDelivery { error in
                DispatchQueue.main.async {
                    if let _ = error {
                        self.failedResume = true
                    } else {
                        self.done()
                    }
                }
            }
        }
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
                        // Exit failed - go back to filling step and show error
                        self.failedExitMode = true
                        self.currentStep = .filling
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.loadingExitMode = false
                    self.failedExitMode = true
                    self.isProcessing = false
                    // No transport - go back to filling step
                    self.currentStep = .filling
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
