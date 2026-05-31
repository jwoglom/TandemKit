import LoopKit
import SwiftUI

class TandemKitG7SetupViewModel: ObservableObject {
    enum Step: Int {
        case landing
        case pairingCode
    }

    @Published var currentStep: Step = .landing
    @Published var pairingCode: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var didComplete: Bool = false

    private let pumpManager: TandemPumpManager?

    init(pumpManager: TandemPumpManager?) {
        self.pumpManager = pumpManager
    }

    // MARK: - Navigation

    func goToPairingCode() {
        currentStep = .pairingCode
    }

    // MARK: - Validation

    var isPairingCodeValid: Bool {
        !pairingCode.isEmpty && pairingCode.allSatisfy { $0.isNumber }
    }

    // MARK: - Start G7 Sensor

    func startG7Sensor() {
        guard isPairingCodeValid, let code = Int(pairingCode) else { return }

        error = nil
        isLoading = true
        
        pumpManager?.connectToG7CGM(code: code) { success in
            DispatchQueue.main.async {
                self.isLoading = false
                self.didComplete = success
                
                if !success {
                    self.error = String(
                        localized: "Failed to set G7 pairing code",
                        comment: "Error when pump is not connected"
                    )
                }
            }
        }
    }
}
