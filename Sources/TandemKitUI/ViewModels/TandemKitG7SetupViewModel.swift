import LoopKit
import SwiftUI
import TandemCore

class TandemKitG7SetupViewModel: ObservableObject {
    @Published var pairingCode: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var didComplete: Bool = false

    private let pumpManager: TandemPumpManager?

    init(pumpManager: TandemPumpManager?) {
        self.pumpManager = pumpManager
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
                    self?.error = LocalizedString(
                        "Pump not connected.",
                        comment: "Error when pump is not connected"
                    )
                }
                return
            }

            let response = pumpManager.sendMessage(
                message: SetDexcomG7PairingCodeRequest(pairingCode: code)
            ) as? SetDexcomG7PairingCodeResponse

            DispatchQueue.main.async {
                self.isLoading = false
                if response?.isStatusOK == true {
                    self.didComplete = true
                } else {
                    self.error = LocalizedString(
                        "Failed to set G7 pairing code. Check pump connection and try again.",
                        comment: "Error when setting G7 pairing code fails"
                    )
                }
            }
        }
    }
}
