import LoopKit
import SwiftUI

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
    @Published var isProcessing = false

    @Published var primeAmount: Double = 0.3 // Default 0.3 units
    @Published var isEditingAmount = false

    @Published var loadingSuspend = false
    @Published var loadingFill = false
    @Published var loadingResume = false

    @Published var failedSuspend = false
    @Published var failedFill = false
    @Published var failedResume = false

    let done: () -> Void
    private let pumpManager: TandemPumpManager?

    init(pumpManager: TandemPumpManager?, done: @escaping () -> Void) {
        self.pumpManager = pumpManager
        self.done = done
    }

    func checkSuspendedStatus() {
        pumpManager?.fetchSuspendStatus { isSuspended in
            DispatchQueue.main.async {
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

        pumpManager?.primeCanulla(amount: primeAmount) { response in
            DispatchQueue.main.async {
                self.loadingFill = false
                self.isProcessing = false
                if let response = response, response.status == 0 {
                    self.failedFill = false
                    self.pumpManager?.recordSiteChange()
                    self.currentStep = self.currentStep.nextStep() ?? .done
                } else {
                    self.failedFill = true
                }
            }
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
