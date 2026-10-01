import Combine
import Foundation
import LoopKit

enum G6SetupStep: Int {
    case landing = 0
    case sensorDetails = 1
    case connectExisting = 2
}

class TandemKitG6SetupViewModel: ObservableObject {
    @Published var currentStep: G6SetupStep = .landing
    @Published var transmitterId: String = ""
    @Published var sensorCode: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var didComplete: Bool = false

    private let pumpManager: TandemPumpManager?

    /// Invoked on the main thread after the pump accepts the sensor configuration, so the caller
    /// can reload any status it is displaying.
    private let onSetupCompleted: (() -> Void)?

    init(pumpManager: TandemPumpManager?, onSetupCompleted: (() -> Void)? = nil) {
        self.pumpManager = pumpManager
        self.onSetupCompleted = onSetupCompleted
    }

    // MARK: - Navigation

    func goToSensorDetails() {
        currentStep = .sensorDetails
    }

    func goToConnectExisting() {
        currentStep = .connectExisting
    }

    // MARK: - Validation

    // ASCII only: isLetter/isNumber also accept "É" or "١", which overrun the request or fail Int().
    var isTransmitterIdValid: Bool {
        transmitterId.count == 6 && transmitterId.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    var isSensorCodeValid: Bool {
        sensorCode.count == 4 && sensorCode.allSatisfy { $0.isASCII && $0.isNumber }
    }

    var canStartSensor: Bool {
        isTransmitterIdValid && isSensorCodeValid
    }

    var canConnectExisting: Bool {
        isTransmitterIdValid
    }

    // MARK: - Connect to Existing Session

    func connectToExistingSession() {
        guard canConnectExisting else { return }

        error = nil
        isLoading = true

        let txId = transmitterId.uppercased()
        pumpManager?.connectToG6CGM(txId: txId, code: nil) { success in
            DispatchQueue.main.async {
                self.isLoading = false
                self.didComplete = success

                if success {
                    self.onSetupCompleted?()
                } else {
                    self.error = String(
                        localized: "Failed to set transmitter.",
                        comment: "Error when pump is not connected"
                    )
                }
            }
        }
    }

    // MARK: - Start Sensor

    func startNewSensor() {
        guard canStartSensor, let code = Int(sensorCode) else { return }

        error = nil
        isLoading = true

        let txId = transmitterId.uppercased()
        pumpManager?.connectToG6CGM(txId: txId, code: code) { success in
            DispatchQueue.main.async {
                self.isLoading = false
                self.didComplete = success

                if success {
                    self.onSetupCompleted?()
                } else {
                    self.error = String(
                        localized: "Failed to start CGM sensor",
                        comment: "Error when pump is not connected"
                    )
                }
            }
        }
    }
}
