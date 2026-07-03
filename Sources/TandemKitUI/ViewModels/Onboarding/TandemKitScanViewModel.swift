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
                self.onPairFailure(error: error)
                return
            }

            self.onPairSuccess()
        }
    }

    func onPairSuccess() {
        // TODO: Uncomment after syncBasal is fixed...
        guard let pumpManager = self.pumpManager else {
            DispatchQueue.main.async {
                self.log.error("No pumpManager")
                self.nextStep()
            }
            return
        }

        pumpManager.syncPumpData { _ in
            DispatchQueue.main.async {
                self.log.info("Pairing successful")
                self.nextStep()
            }
        }

//        let soundRequest = SetPumpSoundsRequest(
//            quickBolusAnnunRaw: pumpManager.lockedState.value.quickBolusAnnun?.rawValue ?? 0,
//            generalAnnunRaw: pumpManager.lockedState.value.generalAnnun?.rawValue ?? 0,
//            reminderAnnunRaw: pumpManager.lockedState.value.reminderAnnun?.rawValue ?? 0,
//            alertAnnunRaw: pumpManager.lockedState.value.alertAnnun?.rawValue ?? 0,
//            alarmAnnunRaw: pumpManager.lockedState.value.alarmAnnun?.rawValue ?? 0,
//            cgmAlertAnnun: 0x0000, // Vibrate
//            changeBitmask: PumpSoundChangeBitmask.all()
//        )
//
//        guard let basalSchedule = pumpManager.lockedState.value.basalRateSchedule else {
//            log.error("No basal schedule")
//            nextStep()
//            return
//        }
//
//        pumpManager.syncBasalRateSchedule(items: basalSchedule.items) { _ in
//            pumpManager.setPumpSound(request: soundRequest)
//            pumpManager.syncPumpTime { _ in
//                DispatchQueue.main.async {
//                    self.log.info("Pairing successful")
//                    self.nextStep()
//                }
//            }
//        }
    }

    func onPairFailure(error: Error) {
        DispatchQueue.main.async {
            self.log.error("Pairing failed: \(error.localizedDescription)")

            // Include the recovery suggestion (e.g. where to find the PIN) when the error
            // provides one, so a wrong-code failure tells the user how to fix it.
            var message = error.localizedDescription
            if let suggestion = (error as? LocalizedError)?.recoverySuggestion, !suggestion.isEmpty {
                message += "\n\n" + suggestion
            }
            self.isConnectionError = true
            self.connectionErrorMessage = message

            // Reset back to a scannable state so the user can re-enter the code instead of
            // being stranded on the pairing spinner.
            self.selectedPeripheral = nil
            self.devicePinCode = ""
            self.currentPhase = .mobiOnPad
            _ = self.pumpManager?.bluetooth.startScan(self.deviceScanDidUpdate)
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
