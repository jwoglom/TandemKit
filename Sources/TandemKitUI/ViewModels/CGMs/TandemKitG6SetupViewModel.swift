import LoopKit
import SwiftUI

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

    init(pumpManager: TandemPumpManager?) {
        self.pumpManager = pumpManager
    }

    // MARK: - Navigation

    func goToSensorDetails() {
        withAnimation {
            currentStep = .sensorDetails
        }
    }

    func goToConnectExisting() {
        withAnimation {
            currentStep = .connectExisting
        }
    }

    // MARK: - Validation

    var isTransmitterIdValid: Bool {
        transmitterId.count == 6 && transmitterId.allSatisfy { $0.isLetter || $0.isNumber }
    }

    var isSensorCodeValid: Bool {
        sensorCode.count == 4 && sensorCode.allSatisfy { $0.isNumber }
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

            // Set sensor type to G6
//            let sensorTypeResponse = pumpManager.sendMessage(
//                message: SetSensorTypeRequest(sensorType: .dexcomG6)
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
//            // Set transmitter ID
//            let txResponse = pumpManager.sendMessage(
//                message: SetG6TransmitterIdRequest(txId: txId)
//            ) as? SetG6TransmitterIdResponse

//            DispatchQueue.main.async {
//                self.isLoading = false
//                if txResponse?.isStatusOK == true {
//                    self.didComplete = true
//                } else {
//                    self.error = String(
//                        localized:
//                        "Failed to set transmitter ID. Check pump connection and try again.",
//                        comment: "Error when setting G6 transmitter ID fails"
//                    )
//                }
//            }
        }
    }

    // MARK: - Start Sensor

    func startNewSensor() {
        guard canStartSensor else { return }

        error = nil
        isLoading = true

        let txId = transmitterId.uppercased()
        let code = Int(sensorCode) ?? 0

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

            // Step 1: Set sensor type to G6
//            let sensorTypeResponse = pumpManager.sendMessage(
//                message: SetSensorTypeRequest(sensorType: .dexcomG6)
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
//            // Step 2: Set transmitter ID
//            let txResponse = pumpManager.sendMessage(
//                message: SetG6TransmitterIdRequest(txId: txId)
//            ) as? SetG6TransmitterIdResponse
//
//            guard txResponse?.isStatusOK == true else {
//                DispatchQueue.main.async {
//                    self.isLoading = false
//                    self.error = String(
//                        localized:
//                        "Failed to set transmitter ID. Check pump connection and try again.",
//                        comment: "Error when setting G6 transmitter ID fails"
//                    )
//                }
//                return
//            }
//
//            // Step 3: Start sensor session
//            let startResponse = pumpManager.sendMessage(
//                message: StartDexcomG6SensorSessionRequest(sensorCode: code)
//            ) as? StartDexcomG6SensorSessionResponse
//
//            DispatchQueue.main.async {
//                self.isLoading = false
//                if startResponse?.isStatusOK == true {
//                    self.didComplete = true
//                } else {
//                    self.error = String(
//                        localized:
//                        "Failed to start CGM sensor. Check pump connection and try again.",
//                        comment: "Error when starting G6 sensor fails"
//                    )
//                }
//            }
        }
    }
}
