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

    /// True when the pump has left fill-tubing mode on its own (Mobi auto-exits after dispensing a set
    /// amount). Drives the explicit "Continue filling" / "Complete tubing fill" choice on the filling step.
    @Published var pumpExitedFillMode = false

    /// Guards against subscribing to the pump-manager streams more than once across continue cycles.
    private var isMonitoringStreams = false

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

    func enterFillTubingMode() {
        performEnterFillTubing(advanceStep: true, startMonitoring: true)
    }

    /// Re-enter fill-tubing mode after the pump auto-exited, so the user can keep filling without
    /// restarting the whole flow. Stays on the `.filling` step and reuses the existing stream
    /// subscriptions (no re-subscribe).
    func continueFilling() {
        pumpExitedFillMode = false
        performEnterFillTubing(advanceStep: false, startMonitoring: false)
    }

    private func performEnterFillTubing(advanceStep: Bool, startMonitoring: Bool) {
        guard isSuspended == true else {
            failedEnterMode = true
            return
        }

        loadingEnterMode = true
        failedEnterMode = false
        isProcessing = true

        pumpManager?.enterFillTubingMode { response in
            DispatchQueue.main.async {
                self.loadingEnterMode = false
                if let response = response, response.status == 0 {
                    self.failedEnterMode = false
                    if advanceStep {
                        self.currentStep = self.currentStep.nextStep() ?? .done
                    }
                    if startMonitoring {
                        self.startMonitoringButtonState()
                    }
                } else {
                    self.failedEnterMode = true
                    if advanceStep {
                        self.isProcessing = false
                    } else {
                        // Re-enter after auto-exit failed: keep the Continue/Complete UI available.
                        self.pumpExitedFillMode = true
                    }
                }
            }
        }
    }

    func startMonitoringButtonState() {
        // Subscribe to pump-manager streams once. `cancellables` lives for the VM's lifetime and is
        // never torn down on auto-exit, so these sinks persist across Continue-filling cycles; the
        // guard prevents duplicate subscriptions if this is reached again.
        guard let pumpManager = pumpManager, !isMonitoringStreams else { return }
        isMonitoringStreams = true

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

        // Detect when the pump auto-exits fill-tubing mode. A `.pumpingStatus` qualifying event makes
        // the pump manager read the load status and publish it here.
        pumpManager.loadStatusStream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] response in
                self?.handleLoadStatus(response)
            }
            .store(in: &cancellables)
    }

    private func handleLoadStatus(_ response: LoadStatusResponse) {
        // Only meaningful once filling is under way; the hasDisplayedFlow gate also ensures a status
        // read that races the initial enter (before any filling) isn't misread as an exit.
        guard currentStep == .filling, hasDisplayedFlow else { return }

        if response.isInTubingFillMode {
            pumpExitedFillMode = false
        } else {
            pumpExitedFillMode = true
            // Make the Continue/Complete UI reachable even if the button stream never reports a
            // release (e.g. the pump auto-exits while the button is still held).
            buttonDown = false
        }
    }

    private func requestAlertStatus() {
        processQueue.async { [weak self] in
//            guard let transport = self?.pumpManager?.pairedTransport else { return }
//            _ = try? transport.sendMessage(AlertStatusRequest()) as? AlertStatusResponse
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

        pumpManager?.resumeDelivery { error in
            if error != nil {
                DispatchQueue.main.async {
                    self.failedResume = true
                }
                return
            }

            self.pumpManager?.syncPumpData { _ in
                DispatchQueue.main.async {
                    self.done()
                }
            }
        }
    }

    func exitFillTubingMode() {
        loadingExitMode = true
        failedExitMode = false

        pumpManager?.exitFillTubingMode { response in
            DispatchQueue.main.async {
                self.loadingExitMode = false
                self.isProcessing = false
                if let response = response, response.status == 0 {
                    self.failedExitMode = false
                    self.exitState = .tubingFilled
                    self.currentStep = self.currentStep.nextStep() ?? .done
                } else if self.pumpExitedFillMode {
                    // The pump already auto-exited fill mode, so re-issuing the exit request is
                    // expected to be rejected. Treat that as success instead of bouncing to filling.
                    self.failedExitMode = false
                    self.exitState = .tubingFilled
                    self.currentStep = .done
                } else {
                    // Exit failed - go back to filling step and show error
                    self.failedExitMode = true
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
