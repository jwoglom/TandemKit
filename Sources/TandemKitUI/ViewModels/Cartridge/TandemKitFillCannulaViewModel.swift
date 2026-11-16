import Combine
import Foundation
import LoopKit

enum CannulaFillStep: Int {
    case suspend = 0
    case enterAmount = 1
    case done = 2

    func nextStep() -> CannulaFillStep? {
        switch self {
        case .suspend:
            return .enterAmount
        case .enterAmount:
            return .done
        case .done:
            return nil
        }
    }
}

class TandemKitFillCannulaViewModel: ObservableObject {
    @Published var currentStep: CannulaFillStep = .suspend
    @Published var isSuspended: Bool? = nil
    @Published var isCheckingSuspendStatus = true
    @Published var isProcessing = false

    @Published var primeAmount: Double
    @Published var isEditingAmount = false

    @Published var loadingSuspend = false
    @Published var loadingFill = false
    @Published var loadingResume = false

    @Published var failedSuspend = false
    @Published var failedFill = false
    @Published var failedResume = false

    let done: () -> Void
    private let pumpManager: TandemPumpManager?
    private var cancellables = Set<AnyCancellable>()
    private var fillResolved = false
    private var fillTimeoutWorkItem: DispatchWorkItem?

    // The pump primes the cannula physically; a real fill completes well within this window.
    // This bound exists purely so the UI can't spin forever if the pump's completion stream
    // message is dropped or never arrives.
    private let fillTimeout: DispatchTimeInterval = .seconds(30)

    /// Prime amounts the wizard offers, in units: the pump refuses a fill over 1.0 U. The picker tags
    /// rows with these exact values, so any amount assigned to `primeAmount` has to come from this
    /// list or the picker will show no selection — `stride` accumulates floating-point error, so
    /// `0.3` is not `options[2]`.
    static let primeAmountOptions: [Double] = Array(stride(from: 0.1, through: 1.0, by: 0.1))

    /// Prime amount used when the user has not filled a cannula before.
    static let defaultPrimeAmount: Double = 0.3

    /// The offered amount closest to `amount`, so a remembered or default value always matches a
    /// picker row exactly.
    static func nearestPrimeAmount(to amount: Double) -> Double {
        primeAmountOptions.min { abs($0 - amount) < abs($1 - amount) } ?? amount
    }

    var showsGraphics: Bool {
        MobiAppGraphic.suits(pumpManager?.state.pumpState.pumpModel)
    }

    init(pumpManager: TandemPumpManager?, done: @escaping () -> Void) {
        self.pumpManager = pumpManager
        self.done = done
        // Pre-fill the amount used for the last successful fill, so a user who always primes the
        // same amount does not have to re-enter it each site change.
        primeAmount = Self.nearestPrimeAmount(
            to: pumpManager?.state.lastCannulaFillAmount ?? Self.defaultPrimeAmount
        )
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
                    self.currentStep = .enterAmount
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

    func fillCannula() {
        guard isSuspended == true else {
            failedFill = true
            return
        }

        loadingFill = true
        failedFill = false
        isProcessing = true
        fillResolved = false

        // The pump signals that the cannula has actually finished filling asynchronously, via a
        // FillCannulaStateStreamResponse (state == .cannulaFilled) on the control-stream
        // characteristic. The direct response to FillCannulaRequest is only an acknowledgment that
        // the pump accepted the command and *started* priming — it arrives almost immediately and
        // must NOT be treated as completion. Subscribe before issuing the command so the completion
        // signal cannot be missed, then wait for it (or the safety timeout) before advancing.
        observeCannulaFilled()

        pumpManager?.primeCanulla(amount: primeAmount) { response in
            DispatchQueue.main.async {
                guard let response = response, response.status == 0 else {
                    // The pump refused to start filling — fail immediately.
                    self.resolveFill(success: false)
                    return
                }
                // Filling has started successfully. Keep the loading state and wait for the
                // .cannulaFilled stream message; do not advance the wizard yet.
            }
        }
    }

    /// Subscribes to the pump's cannula-fill state stream and advances the wizard only when the
    /// pump reports `.cannulaFilled`. Also arms a safety timeout so the UI can't hang if the
    /// completion message never arrives.
    private func observeCannulaFilled() {
        guard let pumpManager = pumpManager else { return }
        cancellables.removeAll()

        pumpManager.fillCannulaStateStream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] response in
                guard response.state == .cannulaFilled else { return }
                self?.resolveFill(success: true)
            }
            .store(in: &cancellables)

        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            self?.resolveFill(success: false)
        }
        fillTimeoutWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + fillTimeout, execute: timeoutWorkItem)
    }

    /// Finalizes the fill exactly once, tearing down the stream subscription and either advancing
    /// the wizard (recording the site change) or surfacing a failure.
    private func resolveFill(success: Bool) {
        guard !fillResolved else { return }
        fillResolved = true
        cancellables.removeAll()
        fillTimeoutWorkItem?.cancel()
        fillTimeoutWorkItem = nil

        loadingFill = false
        isProcessing = false

        if success {
            failedFill = false
            pumpManager?.recordSiteChange(primeAmount: primeAmount)
            currentStep = currentStep.nextStep() ?? .done
        } else {
            failedFill = true
        }
    }

    func resumePumping() {
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
}
