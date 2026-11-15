import Combine
import Foundation
import LoopKit

enum CartridgeChangeStep: Int {
    case suspend = 0
    case enterMode = 1
    case waitingForReady = 2
    case physicalChange = 3
    case completing = 4
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
            return .completing
        case .completing:
            return .done
        case .done:
            return nil
        }
    }
}

class TandemKitChangeCartridgeViewModel: ObservableObject {
    static let cartridgeRetractionUnitsPerSecond: Double = 20
    /// Pump-side setup before retraction starts, so it is paid even with nothing to retract.
    static let readyToChangeFixedOverhead: TimeInterval = 5
    /// Used when no pump manager is attached (previews).
    static let defaultCartridgeCapacity: Double = 200

    @Published var currentStep: CartridgeChangeStep = .suspend
    @Published var isSuspended: Bool? = nil
    @Published var isCheckingSuspendStatus = true
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
    /// Set when the pump refused to enter change mode with delivery suspended and no notification
    /// to blame, which is what a cartridge procedure left open looks like. The view consumes it.
    @Published var stuckModeRecoveryOffered = false
    /// Set when a refused enter found a cartridge detected and its tubing not yet filled, so the
    /// wizard finishes at the fill instead of backing the pump out.
    @Published var foundCartridgeAlreadyLoaded = false

    @Published var changeCartridgeState: EnterChangeCartridgeModeStateStreamResponse.ChangeCartridgeState?

    @Published var cartridgeUnitsRemaining: Double?

    private var readyToChangeWorkItem: DispatchWorkItem?
    private var readyToChangeResolved = false
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
        guard let pumpManager else {
            isCheckingSuspendStatus = false
            return
        }
        isCheckingSuspendStatus = true
        pumpManager.fetchSuspendStatus { isSuspended in
            DispatchQueue.main.async {
                self.isCheckingSuspendStatus = false
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
                self.handleEnterResponse(response, sentAt: sentAt, mayOfferRecovery: true)
            }
        }
    }

    private func handleEnterResponse(
        _ response: EnterChangeCartridgeModeResponse?,
        sentAt: Date,
        mayOfferRecovery: Bool
    ) {
        guard let response = response else {
            // No answer at all: the pump may have entered change mode anyway. Re-sending a
            // signed insulin-affecting request blind is the thing to avoid, so drive the
            // pump back to a known state instead and only then offer a retry.
            recoverFromUnansweredEnterMode()
            return
        }

        if response.status == 0 {
            loadingEnterMode = false
            failedEnterMode = false
            currentStep = currentStep.nextStep() ?? .done
            startMonitoringChangeState(requestSentAt: sentAt)
        } else {
            resumeOpenProcedureOrFail(mayOfferRecovery: mayOfferRecovery)
        }
    }

    /// A refusal is what an unfinished procedure looks like, so the pump's load status says where to
    /// pick it up. Backing out is the wrong move in change mode: the pump takes an exit from it as the
    /// new cartridge being in and starts detecting one, after which it refuses change mode again.
    private func resumeOpenProcedureOrFail(mayOfferRecovery: Bool) {
        pumpManager?.fetchLoadStatus { status in
            DispatchQueue.main.async {
                self.loadingEnterMode = false
                switch status.flatMap({ $0.isLoadingActive ? $0.loadState : nil }) {
                case .changeCartridge:
                    self.resumeInChangeMode()
                case .loadCartridge:
                    self.failedEnterMode = false
                    self.isProcessing = false
                    self.foundCartridgeAlreadyLoaded = true
                    self.currentStep = .done
                default:
                    // The pump answered and refused, so its state is known and a retry is safe.
                    self.failedEnterMode = true
                    self.isProcessing = false
                    if mayOfferRecovery {
                        self.offerStuckModeRecoveryIfNothingElseExplainsTheRefusal()
                    }
                }
            }
        }
    }

    /// The pump retracted when it entered change mode, so the cartridge can come out now.
    private func resumeInChangeMode() {
        readyToChangeWorkItem?.cancel()
        readyToChangeWorkItem = nil
        streamCancellables.removeAll()
        readyToChangeResolved = true

        failedEnterMode = false
        changeCartridgeState = .readyToChange
        currentStep = .physicalChange
    }

    /// Reads the pump afresh rather than trusting the screen: the notification list is only polled
    /// every 15 seconds, and `isSuspended` was last read when the wizard opened.
    private func offerStuckModeRecoveryIfNothingElseExplainsTheRefusal() {
        notificationsViewModel.refreshNotifications { [weak self] in
            guard let self = self, !self.hasActiveNotifications else { return }

            self.pumpManager?.fetchSuspendStatus { isSuspended in
                DispatchQueue.main.async {
                    guard isSuspended == true, self.failedEnterMode else { return }
                    self.stuckModeRecoveryOffered = true
                }
            }
        }
    }

    func recoverFromStuckMode() {
        loadingEnterMode = true
        failedEnterMode = false
        indeterminateEnterMode = false
        isProcessing = true

        pumpManager?.recoverAndReenterChangeCartridgeMode { response in
            DispatchQueue.main.async {
                // Timed from the answer, not the request: the exits ahead of the enter would
                // otherwise eat into the retraction wait, and prompting early is the worse error.
                self.handleEnterResponse(response, sentAt: Date(), mayOfferRecovery: false)
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
    /// delivered, so the wait is `readyToChangeFixedOverhead` plus a traversal scaling with
    /// `capacity - unitsRemaining`: 5 s for a full 200 U cartridge, 15 s for an emptied one. With
    /// no reading, assumes an empty cartridge: waiting too long is an inconvenience, prompting
    /// early is not.
    func readyToChangeDelay(unitsRemaining: Double?, capacity: Double) -> TimeInterval {
        let remaining = min(max(unitsRemaining ?? 0, 0), capacity)
        let retraction = (capacity - remaining) / Self.cartridgeRetractionUnitsPerSecond
        return Self.readyToChangeFixedOverhead + retraction
    }

    func cartridgeInserted() {
        currentStep = currentStep.nextStep() ?? .done
        failedExitMode = false
        pumpManager?.recordCartridgeChange()
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
                    self.failedExitMode = true
                    self.currentStep = .completing
                }
            }
        }
    }

    func cancelOperation() {
        readyToChangeWorkItem?.cancel()
        readyToChangeWorkItem = nil
        streamCancellables.removeAll()

        // Attempt to exit change cartridge mode if we're in it
        if currentStep.rawValue >= CartridgeChangeStep.enterMode.rawValue,
           currentStep.rawValue < CartridgeChangeStep.done.rawValue
        {
            exitChangeCartridgeMode()
        }
    }
}
