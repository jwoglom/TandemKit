import Combine
import Foundation
import LoopKit

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

    /// True while the notification read triggered by the pump button coming back up is running.
    /// The fill cannot be completed until it lands, because it is what tells us whether the pump
    /// stopped the fill and is waiting to be confirmed.
    @Published var isCheckingNotifications = false

    /// Last button state the pump reported, or nil before it has reported any. Used to spot the
    /// moment the button is released rather than reacting to every repeat of the same state.
    private var lastReportedButtonDown: Bool?

    let done: () -> Void
    let toFillingCannula: () -> Void
    private let pumpManager: TandemPumpManager?

    // Notifications
    @Published var notificationsViewModel: TandemKitNotificationsViewModel
    private var notificationCheckTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    var hasActiveNotifications: Bool {
        !notificationsViewModel.notifications.isEmpty
    }

    @Published var isShowingFillPausedPrompt = false
    /// Keeps a poll that lands while the dismissal is in flight from bringing the prompt back.
    private var isAcknowledgingFillPause = false

    private var fillPause: NotificationItem? {
        notificationsViewModel.hiddenNotifications.first(where: \.isFillPause)
    }

    /// Whether the user may finish the fill. Blocked while the pump has something outstanding for
    /// them to acknowledge, and while the post-release notification read is still in flight — until
    /// it returns we cannot tell those two cases apart.
    var canCompleteFill: Bool {
        !hasActiveNotifications && !isCheckingNotifications && fillPause == nil
    }

    /// How often notifications are re-read while the tubing fill screen is up. Short, because the
    /// pump can stop a fill on its own and wait for the user to confirm before delivering more.
    static let notificationPollInterval: TimeInterval = 5

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

        notificationsViewModel.hiding = { [weak self] item in
            self?.currentStep == .filling && item.isFillPause
        }

        Publishers.CombineLatest($currentStep, notificationsViewModel.$hiddenNotifications)
            .sink { [weak self] step, hidden in
                self?.updateFillPausedPrompt(step: step, hidden: hidden)
            }
            .store(in: &cancellables)
    }

    deinit {
        notificationCheckTask?.cancel()
    }

    func startPeriodicNotificationCheck() async {
        // Cancel any existing task
        notificationCheckTask?.cancel()

        let interval = UInt64(Self.notificationPollInterval * 1_000_000_000)
        notificationCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }

                // Refresh notifications
                await MainActor.run {
                    self.notificationsViewModel.refreshNotificationsIfIdle()
                }

                do {
                    try await Task.sleep(nanoseconds: interval)
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
                    self.currentStep = self.currentStep.nextStep() ?? .done
                    self.startMonitoringButtonState()
                } else {
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
                self?.handleButtonState(buttonDown: response.buttonDown)
            }
            .store(in: &cancellables)
    }

    /// Handles one button-state report from the pump's fill tubing stream.
    ///
    /// The pump stops the fill on its own once it has delivered the maximum it will give in one
    /// go, and raises a notification asking the user to confirm before it delivers any more. That
    /// happens exactly when the button comes back up, so the notification state is re-read right
    /// then rather than waiting for the next poll — otherwise the screen offers to complete a fill
    /// the pump has actually paused (#248).
    func handleButtonState(buttonDown isDown: Bool) {
        let previous = lastReportedButtonDown
        lastReportedButtonDown = isDown
        buttonDown = isDown

        if isDown {
            hasDisplayedFlow = true
        }

        guard Self.shouldCheckNotifications(previouslyDown: previous, nowDown: isDown) else { return }
        checkNotificationsAfterRelease()
    }

    /// Whether a button-state report warrants an immediate notification read.
    ///
    /// True when the button just came up: either from a reported press, or on the pump's first
    /// report if that already has the button up, since a press we never saw reported may still
    /// have stopped the fill. Repeats of a state we already have are ignored, so a chatty stream
    /// does not turn into a stream of pump reads.
    static func shouldCheckNotifications(previouslyDown: Bool?, nowDown: Bool) -> Bool {
        guard !nowDown else { return false }
        // Nothing reported yet is treated as a release: a press we never saw is still a press.
        return previouslyDown ?? true
    }

    private func checkNotificationsAfterRelease() {
        isCheckingNotifications = true
        notificationsViewModel.refreshNotifications { [weak self] in
            self?.isCheckingNotifications = false
        }
    }

    private func updateFillPausedPrompt(step: TubingFillStep, hidden: [NotificationItem]) {
        guard step == .filling, hidden.contains(where: \.isFillPause) else {
            isShowingFillPausedPrompt = false
            return
        }
        if !isAcknowledgingFillPause {
            isShowingFillPausedPrompt = true
        }
    }

    func acknowledgeFillPause() {
        guard let pumpManager, let item = fillPause else { return }

        isAcknowledgingFillPause = true
        pumpManager.dismissNotification(notification: item) { [weak self] _ in
            DispatchQueue.main.async {
                self?.notificationsViewModel.refreshNotifications {
                    guard let self else { return }
                    isAcknowledgingFillPause = false
                    updateFillPausedPrompt(step: currentStep, hidden: notificationsViewModel.hiddenNotifications)
                }
            }
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

private extension NotificationItem {
    var isFillPause: Bool {
        type == .alert && notificationId == UInt32(AlertStatusResponse.AlertResponseType.FILL_TUBING_STILL_IN_PROGRESS.rawValue)
    }
}
