import LoopKit
import SwiftUI
import TandemCore

class TandemKitCGMSettingsViewModel: ObservableObject {
    @Published var cgmStatus: CGMStatusResponse?
    @Published var g6TransmitterInfo: GetG6TransmitterHardwareInfoResponse?
    @Published var g7SavedPairingCode: GetSavedG7PairingCodeResponse?

    // G6 fields
    @Published var g6TransmitterId: String = ""
    @Published var g6SensorCode: String = ""

    // G7 fields
    @Published var g7PairingCodeInput: String = ""

    // Loading states
    @Published var isRefreshing = false
    @Published var isStartingG6Session = false
    @Published var isStoppingSession = false
    @Published var isSettingG6Transmitter = false
    @Published var isSettingG7PairingCode = false
    @Published var isGettingG7PairingCode = false

    // Error states
    @Published var errorMessage: String?
    @Published var showingStartG6Confirmation = false
    @Published var showingStartG7Confirmation = false
    @Published var showingStopConfirmation = false

    private let pumpManager: TandemPumpManager?

    init(pumpManager: TandemPumpManager?) {
        self.pumpManager = pumpManager
    }

    func sendMessage(message: Message) -> Message? {
        guard let transport = pumpManager?.pairedTransport else {
            return nil
        }

        return try? transport.sendMessage(message)
    }

    func refreshCGMStatus() {
        isRefreshing = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let status = self.sendMessage(message: CGMStatusRequest()) as? CGMStatusResponse
            let g6Info = self.sendMessage(message: GetG6TransmitterHardwareInfoRequest()) as? GetG6TransmitterHardwareInfoResponse
            let g7Code = self.sendMessage(message: GetSavedG7PairingCodeRequest()) as? GetSavedG7PairingCodeResponse

            DispatchQueue.main.async {
                self.cgmStatus = status
                self.g6TransmitterInfo = g6Info
                self.g7SavedPairingCode = g7Code
                self.isRefreshing = false
            }
        }
    }

    // MARK: - G6 Operations

    func setG6TransmitterId() {
        guard !g6TransmitterId.isEmpty else {
            errorMessage = "Please enter a transmitter ID"
            return
        }

        guard g6TransmitterId.count == 6 else {
            errorMessage = "Transmitter ID must be 6 characters"
            return
        }

        isSettingG6Transmitter = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let response = self
                .sendMessage(message: SetG6TransmitterIdRequest(txId: self.g6TransmitterId)) as? SetG6TransmitterIdResponse

            DispatchQueue.main.async {
                self.isSettingG6Transmitter = false

                if let response = response {
                    if response.status == 0 {
                        self.g6TransmitterId = ""
                        self.refreshCGMStatus()
                    } else {
                        self.errorMessage = "Failed to set transmitter ID (status: \(response.status))"
                    }
                } else {
                    self.errorMessage = "Failed to communicate with pump"
                }
            }
        }
    }

    func startG6SensorSession() {
        let sensorCode = Int(g6SensorCode) ?? 0

        isStartingG6Session = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let response = self
                .sendMessage(
                    message: StartDexcomG6SensorSessionRequest(sensorCode: sensorCode)
                ) as? StartDexcomG6SensorSessionResponse

            Thread.sleep(forTimeInterval: 1.0)

            DispatchQueue.main.async {
                self.isStartingG6Session = false

                if let response = response {
                    if response.status == 0 {
                        self.g6SensorCode = ""
                        self.refreshCGMStatus()
                    } else {
                        self.errorMessage = "Failed to start G6 session (status: \(response.status))"
                    }
                } else {
                    self.errorMessage = "Failed to communicate with pump"
                }
            }
        }
    }

    // MARK: - G7 Operations

    func setG7PairingCode() {
        guard !g7PairingCodeInput.isEmpty else {
            errorMessage = "Please enter a pairing code"
            return
        }

        guard let pairingCode = Int(g7PairingCodeInput) else {
            errorMessage = "Pairing code must be numeric"
            return
        }

        isSettingG7PairingCode = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let response = self
                .sendMessage(message: SetDexcomG7PairingCodeRequest(pairingCode: pairingCode)) as? SetDexcomG7PairingCodeResponse

            Thread.sleep(forTimeInterval: 1.0)

            DispatchQueue.main.async {
                self.isSettingG7PairingCode = false

                if let response = response {
                    if response.status == 0 {
                        self.g7PairingCodeInput = ""
                        self.refreshCGMStatus()
                    } else {
                        self.errorMessage = "Failed to set G7 pairing code (status: \(response.status))"
                    }
                } else {
                    self.errorMessage = "Failed to communicate with pump"
                }
            }
        }
    }

    func getSavedG7PairingCode() {
        isGettingG7PairingCode = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let response = self.sendMessage(message: GetSavedG7PairingCodeRequest()) as? GetSavedG7PairingCodeResponse

            DispatchQueue.main.async {
                self.isGettingG7PairingCode = false

                if let response = response {
                    self.g7SavedPairingCode = response
                    self.errorMessage = "Saved pairing code: \(String(response.pairingCode))"
                } else {
                    self.errorMessage = "Failed to get saved pairing code"
                }
            }
        }
    }

    // MARK: - Common Operations

    func stopCGMSession() {
        isStoppingSession = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let response = self.sendMessage(message: StopDexcomCGMSensorSessionRequest()) as? StopDexcomCGMSensorSessionResponse

            Thread.sleep(forTimeInterval: 1.0)

            DispatchQueue.main.async {
                self.isStoppingSession = false

                if let response = response {
                    if response.status == 0 {
                        self.refreshCGMStatus()
                    } else {
                        self.errorMessage = "Failed to stop CGM session (status: \(response.status))"
                    }
                } else {
                    self.errorMessage = "Failed to communicate with pump"
                }
            }
        }
    }

    var sessionStateText: String {
        guard let status = cgmStatus else {
            return "Unknown"
        }

        switch status.sessionState {
        case .sessionStopped:
            return "Stopped"
        case .sessionStartPending:
            return "Start Pending"
        case .sessionActive:
            return "Active"
        case .sessionStopPending:
            return "Stop Pending"
        case .none:
            return "Unknown"
        }
    }

    var isSessionActive: Bool {
        cgmStatus?.sessionState == .sessionActive
    }
}
