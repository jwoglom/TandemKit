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

    /// Setup stops here when the pump will not take the app's settings. Advancing anyway would hand
    /// the user a paired pump running a profile the app is not reporting, which is issue #206.
    func applyOnboardingSettings() {
        guard let pumpManager = self.pumpManager else {
            DispatchQueue.main.async {
                self.log.error("No pumpManager")
                self.nextStep()
            }
            return
        }

        pumpManager.applyOnboardingSettings { error in
            if let error {
                self.log.error("Failed to apply onboarding settings: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.settingsErrorMessage = error.localizedDescription
                    self.isSettingsError = true
                }
                return
            }

            pumpManager.syncPumpData { _ in
                DispatchQueue.main.async {
                    self.log.info("Pairing successful")
                    self.nextStep()
                }
            }
        }
    }

    func continueWithoutOnboardingSettings() {
        log.error("Continuing setup with the pump holding settings the app could not write")
        nextStep()
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
