import LoopKit
import SwiftUI
import TandemCore

enum CannulaFillStep: Int {
    case suspend = 0
    case enterAmount = 1
    case filling = 2
    case done = 3

    func nextStep() -> CannulaFillStep? {
        switch self {
        case .suspend:
            return .enterAmount
        case .enterAmount:
            return .filling
        case .filling:
            return .done
        case .done:
            return nil
        }
    }
}

class TandemKitFillCannulaViewModel: ObservableObject {
    @Published var currentStep: CannulaFillStep = .suspend
    @Published var isSuspended = false
    @Published var isProcessing = false

    @Published var primeAmount: Double = 0.3 // Default 0.3 units
    @Published var isEditingAmount = false

    @Published var loadingSuspend = false
    @Published var loadingFill = false

    @Published var failedSuspend = false
    @Published var failedFill = false

    @Published var showingSuspendConfirmation = false
    @Published var showingCancelConfirmation = false
    @Published var showingResumeConfirmation = false

    private let pumpManager: TandemPumpManager?
    private let processQueue = DispatchQueue(label: "TandemKit.cannula.processQueue")

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
                    if self.isSuspended, self.currentStep == .suspend {
                        self.currentStep = .enterAmount
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

    func fillCannula() {
        guard isSuspended else {
            failedFill = true
            return
        }

        loadingFill = true
        failedFill = false
        isProcessing = true

        let milliUnits = Int(primeAmount * 1000)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let transport = self.pumpManager?.pairedTransport {
                let response = try? transport
                    .sendMessage(FillCannulaRequest(primeSizeMilliUnits: milliUnits)) as? FillCannulaResponse

                Thread.sleep(forTimeInterval: Double(self.primeAmount) * 2.0) // Simulate delivery time

                DispatchQueue.main.async {
                    self.loadingFill = false
                    self.isProcessing = false
                    if let response = response, response.status == 0 {
                        self.failedFill = false
                        self.currentStep = self.currentStep.nextStep() ?? .done
                    } else {
                        self.failedFill = true
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.loadingFill = false
                    self.failedFill = true
                    self.isProcessing = false
                }
            }
        }
    }

    func resumePumping() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let transport = self.pumpManager?.pairedTransport {
                _ = try? transport.sendMessage(ResumePumpingRequest())

                Thread.sleep(forTimeInterval: 1.0)
                self.checkSuspendedStatus()
            }
        }
    }
}
