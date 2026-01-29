import CoreBluetooth
import LoopKit
import SwiftUI
import TandemCore

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

        self.pumpManager?.addScanDeviceObserver(self, queue: .main)
    }

    func startScan() {
        pumpManager?.setScanningMode(true)
        pumpManager?.tandemPump.startScanning()
    }

    func stopScan() {
        pumpManager?.setScanningMode(false)
        pumpManager?.tandemPump.stopScanning()
    }

    func cancelPinPrompt() {
        isPromptingPincode = false
        selectedPeripheral = nil
        devicePinCode = ""

        // Clear the target peripheral filter
        pumpManager?.setTargetPeripheral(nil)

        // Restart scanning
        pumpManager?.setScanningMode(true)
        pumpManager?.tandemPump.startScanning()
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

        // Set the target peripheral so the manager only connects to this specific device
        pumpManager.setTargetPeripheral(peripheral.identifier)

        pumpManager.pairPump(with: devicePinCode, peripheral: peripheral) { result in
            switch result {
            case let .failure(error):
                self.onPairFailure(error: error)
            case .success:
                self.onPairSuccess()
            }
        }
    }

    func onPairSuccess() {
        DispatchQueue.main.async {
            self.log.info("Pairing successful")
            self.nextStep()
        }

        // TODO: Uncomment after syncBasal is fixed...
//        guard let pumpManager = self.pumpManager else {
//            log.error("No pumpManager")
//            nextStep()
//            return
//        }
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
//            self.log.info("Done syncing basal!")
//            pumpManager.setPumpSound(request: soundRequest)
//            self.log.info("Done syncing sound!")
//            DispatchQueue.main.async {
//                self.log.info("Pairing successful")
//                self.nextStep()
//            }
//        }
    }

    func onPairFailure(error: Error) {
        DispatchQueue.main.async {
            self.pumpManager?.setTargetPeripheral(nil)

            self.log.error("Pairing failed: \(error.localizedDescription)")
            self.isConnectionError = true
            self.connectionErrorMessage = error.localizedDescription
            self.selectedPeripheral = nil
            self.devicePinCode = ""
        }
    }

    deinit {
        pumpManager?.removeScanDeviceObserver(self)
    }
}

extension TandemKitScanViewModel: StateObserver {
    func deviceScanDidUpdate(_ device: TandemPumpScan) {
        if selectedPeripheral == nil {
            selectedPeripheral = device.peripheral
            connectingTo = device.name
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
            currentPhase = .mobiOnPad
            return
        }

        if pairingState == 0x11 {
            currentPhase = .doubleTap
            return
        }

        if pairingState == 0x12 {
            log.info("Enter pincode state!")
            stopScan()
            isPromptingPincode = true
            return
        }
    }
}
