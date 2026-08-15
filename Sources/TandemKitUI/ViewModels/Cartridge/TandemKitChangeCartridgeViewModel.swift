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
    /// The pump never answered the enter request and could not be driven back out of change mode,
    /// so which mode it is in is unknown and retrying blind is unsafe.
    @Published var indeterminateEnterMode = false

    @Published var changeCartridgeState: EnterChangeCartridgeModeStateStreamResponse.ChangeCartridgeState?
    @Published var detectingProgress: Int = 0
    @Published var isDetecting = false

    @Published var cartridgeUnitsRemaining: Double?

    private var readyToChangeWorkItem: DispatchWorkItem?
    private var readyToChangeResolved = false
    private var simulatedDetectingTimer: Timer?
    private var detectingResolved = false
    private var streamCancellables = Set<AnyCancellable>()

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
        simulatedDetectingTimer?.invalidate()
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
        indeterminateEnterMode = false
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
                guard let response = response else {
                    // No answer at all: the pump may have entered change mode anyway. Re-sending a
                    // signed insulin-affecting request blind is the thing to avoid, so drive the
                    // pump back to a known state instead and only then offer a retry.
                    self.recoverFromUnansweredEnterMode()
                    return
                }

                self.loadingEnterMode = false
                if response.status == 0 {
                    self.failedEnterMode = false
                    self.currentStep = self.currentStep.nextStep() ?? .done
                    self.startMonitoringChangeState(requestSentAt: sentAt)
                } else {
                    // The pump answered and refused, so its state is known and a retry is safe.
                    self.failedEnterMode = true
                    self.isProcessing = false
                }
            }
        }
    }

    private func recoverFromUnansweredEnterMode() {
        pumpManager?.exitChangeCartridgeMode { response in
            DispatchQueue.main.async {
                self.loadingEnterMode = false
                self.isProcessing = false

                if let response = response, response.status == 0 {
                    // Known to be out of change mode now, so the user can safely try again.
                    self.failedEnterMode = true
                } else {
                    self.indeterminateEnterMode = true
                }
            }
        }
    }

    /// Advances on whichever comes first: the pump's own `.readyToChange`, or the estimate in
    /// `readyToChangeDelay`. The estimate exists because the change-cartridge stream is not
    /// currently emitting; the pump's signal takes precedence whenever it does arrive.
    func startMonitoringChangeState(requestSentAt: Date) {
        let capacity = pumpManager?.pumpReservoirCapacity ?? Self.defaultCartridgeCapacity
        let delay = readyToChangeDelay(unitsRemaining: cartridgeUnitsRemaining, capacity: capacity)
        let remaining = max(0, delay - Date().timeIntervalSince(requestSentAt))

        changeCartridgeState = nil
        readyToChangeResolved = false
        readyToChangeWorkItem?.cancel()

        pumpManager?.changeCartridgeStateStream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] response in
                guard response.state == .readyToChange else { return }
                self?.resolveReadyToChange()
            }
            .store(in: &streamCancellables)

        let workItem = DispatchWorkItem { [weak self] in
            self?.resolveReadyToChange()
        }
        readyToChangeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: workItem)
    }

    private func resolveReadyToChange() {
        guard !readyToChangeResolved else { return }
        readyToChangeResolved = true
        streamCancellables.removeAll()
        readyToChangeWorkItem?.cancel()
        readyToChangeWorkItem = nil

        changeCartridgeState = .readyToChange
        currentStep = currentStep.nextStep() ?? .done
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
        detectingResolved = false
        simulatedDetectingTimer?.invalidate()

        // Real progress takes over as soon as the pump reports any. The simulated ramp below only
        // drives the bar while the detecting stream stays dark, which is its current state.
        pumpManager?.detectingCartridgeStateStream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] response in
                guard let self = self else { return }
                self.simulatedDetectingTimer?.invalidate()
                self.simulatedDetectingTimer = nil
                self.detectingProgress = min(max(response.percentComplete, 0), 100)

                if response.isComplete {
                    self.finishDetecting()
                }
            }
            .store(in: &streamCancellables)

        simulatedDetectingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            DispatchQueue.main.async {
                self.detectingProgress += 10

                if self.detectingProgress >= 100 {
                    self.finishDetecting()
                }
            }
        }
    }

    private func finishDetecting() {
        guard !detectingResolved else { return }
        detectingResolved = true
        simulatedDetectingTimer?.invalidate()
        simulatedDetectingTimer = nil
        streamCancellables.removeAll()

        detectingProgress = 100
        isDetecting = false
        pumpManager?.recordCartridgeChange()
        // Exit change cartridge mode before completing
        exitChangeCartridgeMode()
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
        simulatedDetectingTimer?.invalidate()
        simulatedDetectingTimer = nil
        streamCancellables.removeAll()

        // Attempt to exit change cartridge mode if we're in it
        if currentStep.rawValue >= CartridgeChangeStep.enterMode.rawValue,
           currentStep.rawValue < CartridgeChangeStep.done.rawValue
        {
            exitChangeCartridgeMode()
        }
    }
}
