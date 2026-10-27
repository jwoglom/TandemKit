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
    @Published var connectionErrorTitle = String(
        localized: "Error while connecting to device",
        comment: "Connection error message"
    )
    @Published var connectionErrorMessage: String?
    @Published var devicePinCode = ""
    @Published var isConnectedElsewhere = false
    @Published var connectedElsewhereName = ""

    private let log = TandemLogger(category: "TandemKitScanViewModel")
    private var pumpManager: TandemPumpManager?
    private var nextStep: () -> Void
    private var selectedPeripheral: CBPeripheral?
    private var connectedCheckTimer: Timer?
    private var connectedCheckSilencedUntil = Date.distantPast
    static let connectedAlertSilenceInterval: TimeInterval = 10

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
        stopCheckingForConnectedPump()
    }

    /// A pump connected to the phone elsewhere does not advertise, so pairing could never find it.
    func startCheckingForConnectedPump() {
        connectedCheckTimer?.invalidate()
        checkForConnectedPump()
        connectedCheckTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.checkForConnectedPump()
        }
    }

    func stopCheckingForConnectedPump() {
        connectedCheckTimer?.invalidate()
        connectedCheckTimer = nil
    }

    func checkForConnectedPump() {
        guard currentPhase == .mobiOnPad, !isConnectedElsewhere, Date() >= connectedCheckSilencedUntil,
              let name = pumpManager?.bluetooth.connectedPumpNames().first
        else {
            return
        }
        connectedElsewhereName = name
        isConnectedElsewhere = true
    }

    func connectedElsewhereDismissed() {
        isConnectedElsewhere = false
        connectedCheckSilencedUntil = Date().addingTimeInterval(Self.connectedAlertSilenceInterval)
    }

    var connectedElsewhereMessage: String {
        String(format: String(
            localized: "The device %@ is currently connected to this phone. Please go to iOS Bluetooth Settings, tap %@ and choose Forget, then come back to this screen.",
            comment: "Pairing warning when the pump is already connected to the phone (1: pump name, 2: pump name)"
        ), connectedElsewhereName, connectedElsewhereName)
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
        DispatchQueue.main.async {
            self.log.info("Pairing successful")
            self.nextStep()
        }
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
    /// The pairing step a scan result advertises: the last byte of a pump's manufacturer data. The
    /// unified pump simulator, a CoreBluetooth peripheral fronting faketandem, cannot advertise any,
    /// so it is known by its name (`TandemPumpScan.isSimulatorName`); its pairing state is set on
    /// the simulator, so it is taken as ready for the code. The advertised name comes first: for a
    /// Mac it has connected to before, CoreBluetooth names the peripheral by the Mac's own.
    static func advertisedPairingStep(name: String, advertisementData: [String: Any]?) -> UInt8? {
        if TandemPumpScan.isSimulatorName(advertisementData?[CBAdvertisementDataLocalNameKey] as? String ?? name) {
            return 0x12
        }
        return (advertisementData?[CBAdvertisementDataManufacturerDataKey] as? Data)?.last
    }

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

        guard let pairingState = Self.advertisedPairingStep(name: device.name, advertisementData: device.advertisementData)
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
