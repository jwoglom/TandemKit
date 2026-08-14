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
    static let cartridgeRetractionUnitsPerSecond: Double = 20
    /// Used when no pump manager is attached (previews).
    static let defaultCartridgeCapacity: Double = 200

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

    @Published var cartridgeUnitsRemaining: Double?

    private var readyToChangeWorkItem: DispatchWorkItem?

    let done: () -> Void
    let toFillTubing: () -> Void
    private let pumpManager: TandemPumpManager?

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
        readyToChangeWorkItem?.cancel()
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
                    self.notificationsViewModel.refreshNotificationsIfIdle()
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

        // Read before entering change mode; the pump starts retracting as soon as it's entered.
        pumpManager?.fetchReservoirStatus { units in
            DispatchQueue.main.async {
                self.cartridgeUnitsRemaining = units
                self.sendEnterChangeCartridgeMode()
            }
        }
    }

    private func sendEnterChangeCartridgeMode() {
        let sentAt = Date()

        pumpManager?.enterChangeCartridgeMode { response in
            DispatchQueue.main.async {
                self.loadingEnterMode = false
                if let response = response, response.status == 0 {
                    self.failedEnterMode = false
                    self.currentStep = self.currentStep.nextStep() ?? .done
                    self.startMonitoringChangeState(requestSentAt: sentAt)
                } else {
                    self.failedEnterMode = true
                    self.isProcessing = false
                }
            }
        }
    }

    /// Estimates the ready state instead of observing it, since the pump isn't currently emitting
    /// the change-cartridge control stream. Switch to `EnterChangeCartridgeModeStateStreamResponse`
    /// `.readyToChange` once it works.
    func startMonitoringChangeState(requestSentAt: Date) {
        let capacity = pumpManager?.pumpReservoirCapacity ?? Self.defaultCartridgeCapacity
        let delay = readyToChangeDelay(unitsRemaining: cartridgeUnitsRemaining, capacity: capacity)
        let remaining = max(0, delay - Date().timeIntervalSince(requestSentAt))

        changeCartridgeState = nil
        readyToChangeWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.changeCartridgeState = .readyToChange
            self.currentStep = self.currentStep.nextStep() ?? .done
        }
        readyToChangeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: workItem)
    }

    /// The pump retracts a drive mechanism that has advanced in proportion to the insulin already
    /// delivered, so the wait scales with `capacity - unitsRemaining`. With no reading, assumes an
    /// empty cartridge: waiting too long is an inconvenience, prompting early is not.
    func readyToChangeDelay(unitsRemaining: Double?, capacity: Double) -> TimeInterval {
        let remaining = min(max(unitsRemaining ?? 0, 0), capacity)
        return (capacity - remaining) / Self.cartridgeRetractionUnitsPerSecond
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
                    self.pumpManager?.recordCartridgeChange()
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
        readyToChangeWorkItem?.cancel()
        readyToChangeWorkItem = nil

        // Attempt to exit change cartridge mode if we're in it
        if currentStep.rawValue >= CartridgeChangeStep.enterMode.rawValue,
           currentStep.rawValue < CartridgeChangeStep.done.rawValue
        {
            exitChangeCartridgeMode()
        }
    }
}
