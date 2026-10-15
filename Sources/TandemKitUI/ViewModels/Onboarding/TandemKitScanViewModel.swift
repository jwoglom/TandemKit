import Combine
import CoreBluetooth
import Foundation
import LoopKit

enum PairingPhase: Int {
    case mobiOnPad = 0
    case doubleTap = 1
    case pairing = 2
}

class TandemKitScanViewModel: ObservableObject {
    @Published var currentPhase = PairingPhase.mobiOnPad
    @Published var connectingTo: String?
    @Published var isPromptingPincode = false
    @Published var pinCodePromptError: String?
    @Published var isConnectionError = false
    @Published var isSettingsError = false
    @Published var settingsErrorMessage: String?
    @Published var isPromptingControlIQOff = false
    @Published var isControlIQOffError = false
    @Published var controlIQOffErrorMessage: String?
    @Published var connectionErrorTitle = String(
        localized: "Error while connecting to device",
        comment: "Connection error message"
    )
    @Published var connectionErrorMessage: String?
    @Published var devicePinCode = ""

    private let log = TandemLogger(category: "TandemKitScanViewModel")
    private var pumpManager: TandemPumpManager?
    private var nextStep: () -> Void
    private var selectedPeripheral: CBPeripheral?

    init(_ pumpManager: TandemPumpManager? = nil, nextStep: @escaping () -> Void) {
        self.pumpManager = pumpManager
        self.nextStep = nextStep
    }

    func startScan() {
        guard let pumpManager, pumpManager.bluetooth.startScan(deviceScanDidUpdate) else {
            log.error("Failed to start scan")
            return
        }
    }

    func stopScan() {
        pumpManager?.bluetooth.stopScan()
    }

    func cancelPinPrompt() {
        isPromptingPincode = false
        selectedPeripheral = nil
        devicePinCode = ""

        // Restart scanning
        _ = pumpManager?.bluetooth.startScan(deviceScanDidUpdate)
    }

    func processPinPrompt() {
        guard !devicePinCode.isEmpty else {
            pinCodePromptError = String(
                localized: "Please enter a pairing code",
                comment: "Error when the pairing code field is empty"
            )
            return
        }

        isPromptingPincode = false

        guard let pumpManager = pumpManager else {
            isConnectionError = true
            connectionErrorMessage = String(
                localized: "Pump manager not initialized",
                comment: "Pairing error when the pump manager is missing"
            )
            return
        }

        guard let peripheral = selectedPeripheral else {
            isConnectionError = true
            connectionErrorMessage = String(
                localized: "No peripheral selected",
                comment: "Pairing error when no pump was chosen from the scan results"
            )
            return
        }

        currentPhase = .pairing

        pumpManager.pairPump(code: devicePinCode, peripheral: peripheral) { error in
            if let error {
                self.onPairFailure(error: error)
                return
            }

            self.onPairSuccess()
        }
    }

    func onPairSuccess() {
        guard let pumpManager else {
            applyOnboardingSettings()
            return
        }

        pumpManager.controlIQNeedsTurningOffForSetup { needsTurningOff in
            DispatchQueue.main.async {
                if needsTurningOff {
                    self.isPromptingControlIQOff = true
                } else {
                    self.applyOnboardingSettings()
                }
            }
        }
    }

    var controlIQOffPromptMessage: String {
        String(format: String(
            localized: "The pump currently has Control-IQ on. Continuing will turn Control-IQ off, so that %@ uses its own algorithm to control insulin delivery.",
            comment: "Setup message when the paired pump is running Control-IQ (1: app name)"
        ), HostApp.current.appName)
    }

    func turnOffControlIQ() {
        guard let pumpManager else {
            applyOnboardingSettings()
            return
        }

        pumpManager.turnOffControlIQForSetup { error in
            DispatchQueue.main.async {
                guard let error else {
                    self.applyOnboardingSettings()
                    return
                }
                self.controlIQOffErrorMessage = Self.controlIQOffFailureMessage(for: error)
                self.isControlIQOffError = true
            }
        }
    }

    static func controlIQOffFailureMessage(for error: Error) -> String {
        let summary = String(format: String(
            localized: "Control-IQ is still on, and setup can't finish until it is off so that %@ can control insulin delivery. Keep the pump near your phone and try again.",
            comment: "Setup error when turning Control-IQ off did not reach the pump (1: app name)"
        ), HostApp.current.appName)
        return "\(summary)\n\n\(error.localizedDescription)"
    }

    /// On failure, setup waits on the alert instead of advancing, because the pump would otherwise
    /// be left running basal rates the app doesn't know about (#206).
    func applyOnboardingSettings() {
        guard let pumpManager = self.pumpManager else {
            DispatchQueue.main.async {
                self.log.error("No pumpManager")
                self.nextStep()
            }
            return
        }

        pumpManager.applyOnboardingSettings { failure in
            guard let failure else {
                self.finishSetup(pumpManager)
                return
            }

            self.log.error(
                "Failed to apply onboarding settings: basal \(failure.basalSchedule?.localizedDescription ?? "ok"), limits \(failure.deliveryLimits?.localizedDescription ?? "ok")"
            )
            DispatchQueue.main.async {
                self.settingsErrorMessage = Self.message(for: failure)
                self.isSettingsError = true
            }
        }
    }

    func continueWithoutOnboardingSettings() {
        log.error("Continuing setup with the pump holding settings the app could not write")
        guard let pumpManager else {
            nextStep()
            return
        }
        finishSetup(pumpManager)
    }

    private func finishSetup(_ pumpManager: TandemPumpManager) {
        pumpManager.syncPumpData { _ in
            DispatchQueue.main.async {
                self.log.info("Pairing successful")
                self.nextStep()
            }
        }
    }

    static func message(for failure: OnboardingSettingsFailure) -> String {
        let summary: String
        switch (failure.basalSchedule, failure.deliveryLimits) {
        case (.some, .some):
            summary = String(
                localized: "Your basal rates and delivery limits were not saved to the pump. The pump is still using its own settings, so it may not deliver what the app shows. The app will not set temporary basal rates until your basal rates are saved to the pump.",
                comment: "Setup error when neither the basal schedule nor the delivery limits reached the pump"
            )
        case (.some, .none):
            summary = String(
                localized: "Your basal rates were not saved to the pump. The pump is still using its own basal rates, so it may not deliver what the app shows. The app will not set temporary basal rates until your basal rates are saved to the pump.",
                comment: "Setup error when the basal schedule did not reach the pump"
            )
        default:
            summary = String(
                localized: "Your delivery limits were not saved to the pump. The pump is still using its own maximum basal and bolus limits.",
                comment: "Setup error when the delivery limits did not reach the pump"
            )
        }

        guard let detail = failure.basalSchedule ?? failure.deliveryLimits else {
            return summary
        }
        return "\(summary)\n\n\(detail.localizedDescription)"
    }

    /// Leaves the pairing step: the pump is not going to answer, and the scan has to run again for
    /// the pairing code prompt (or the instructions before it) to come back.
    func onPairFailure(error: Error) {
        DispatchQueue.main.async {
            self.log.error("Pairing failed: \(error.localizedDescription)")
            self.connectionErrorTitle = Self.pairingFailureTitle(for: error)
            self.connectionErrorMessage = Self.pairingFailureMessage(for: error)
            self.isConnectionError = true
            self.selectedPeripheral = nil
            self.devicePinCode = ""
            self.currentPhase = .doubleTap
        }
    }

    /// Scanning waits for the alert to be dismissed: the pump may already be showing its pairing
    /// state, and the code prompt is itself an alert.
    func connectionErrorDismissed() {
        startScan()
    }

    static func pairingFailureTitle(for error: Error) -> String {
        if case PumpCommError.pairingCodeRejected = error {
            return String(
                localized: "Pairing Code Not Accepted",
                comment: "Title of the error when the pump did not accept the pairing code"
            )
        }
        return String(localized: "Pairing Failed", comment: "Title of the error when pairing with the pump did not complete")
    }

    static func pairingFailureMessage(for error: Error) -> String {
        let description = error.localizedDescription
        guard let suggestion = (error as? LocalizedError)?.recoverySuggestion, !suggestion.isEmpty else {
            return description
        }
        return "\(description)\n\n\(suggestion)"
    }
}

extension TandemKitScanViewModel {
    func deviceScanDidUpdate(_ device: TandemPumpScan) {
        if selectedPeripheral == nil {
            selectedPeripheral = device.peripheral
            DispatchQueue.main.async {
                self.connectingTo = device.name
            }
        } else if let selectedPeripheral = selectedPeripheral, selectedPeripheral.identifier != device.peripheral.identifier {
            // Ignore other device
            // TODO: Show error if we detect multiple Mobi's
            return
        }

        guard let advertisementData = device.advertisementData,
              let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              let pairingState = manufacturerData.last
        else {
            return
        }

        if pairingState == 0x10 {
            DispatchQueue.main.async {
                self.currentPhase = .mobiOnPad
            }
            return
        }

        if pairingState == 0x11 {
            DispatchQueue.main.async {
                self.currentPhase = .doubleTap
            }
            return
        }

        if pairingState == 0x12 {
            log.info("Enter pincode state!")
            stopScan()
            DispatchQueue.main.async {
                self.isPromptingPincode = true
            }
            return
        }
    }
}
