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

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let pumpManager = self.pumpManager else {
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.error = String(
                        localized:
                        "Pump not connected.",
                        comment: "Error when pump is not connected"
                    )
                }
                return
            }

            // Set sensor type to G7
//            let sensorTypeResponse = pumpManager.sendMessage(
//                message: SetSensorTypeRequest(sensorType: .dexcomG7)
//            ) as? SetSensorTypeResponse
//
//            guard sensorTypeResponse?.isStatusOK == true else {
//                DispatchQueue.main.async {
//                    self.isLoading = false
//                    self.error = String(
//                        localized:
//                        "Failed to set sensor type. Check pump connection and try again.",
//                        comment: "Error when setting sensor type fails"
//                    )
//                }
//                return
//            }
//
//            // Set G7 pairing code
//            let response = pumpManager.sendMessage(
//                message: SetDexcomG7PairingCodeRequest(pairingCode: code)
//            ) as? SetDexcomG7PairingCodeResponse
//
//            DispatchQueue.main.async {
//                self.isLoading = false
//                if response?.isStatusOK == true {
//                    self.didComplete = true
//                } else {
//                    self.error = String(
//                        localized:
//                        "Failed to set G7 pairing code. Check pump connection and try again.",
//                        comment: "Error when setting G7 pairing code fails"
//                    )
//                }
//            }
        }
    }
}
