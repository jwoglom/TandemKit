import CoreBluetooth
import LoopKit
import SwiftUI

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
            pinCodePromptError = "Please enter a pairing code"
            return
        }

        isPromptingPincode = false
        currentPhase = .pairing

        guard let pumpManager = pumpManager else {
            isConnectionError = true
            connectionErrorMessage = "Pump manager not initialized"
            return
        }

        guard let peripheral = selectedPeripheral else {
            isConnectionError = true
            connectionErrorMessage = "No peripheral selected"
            return
        }

        pumpManager.pairPump(code: devicePinCode, peripheral: peripheral) { error in
            if let error {
                self.log.error("Error during pairing: \(error.localizedDescription)")
                return
            }

            self.onPairSuccess()
        }
    }

    func onPairSuccess() {
        applyOnboardingSettings()
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
                localized: "Your basal rates and delivery limits were not saved to the pump. The pump is still using its own settings, so it may not deliver what the app shows.",
                comment: "Setup error when neither the basal schedule nor the delivery limits reached the pump"
            )
        case (.some, .none):
            summary = String(
                localized: "Your basal rates were not saved to the pump. The pump is still using its own basal rates, so it may not deliver what the app shows.",
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

    func onPairFailure(error: Error) {
        DispatchQueue.main.async {
            self.log.error("Pairing failed: \(error.localizedDescription)")
            self.isConnectionError = true
            self.connectionErrorMessage = error.localizedDescription
            self.selectedPeripheral = nil
            self.devicePinCode = ""
        }
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
