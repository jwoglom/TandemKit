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
    @Published var devicePinCode = "" {
        didSet {
            let digits = String(devicePinCode.filter { $0.isASCII && $0.isNumber }.prefix(Self.pairingCodeLength))
            if digits != devicePinCode {
                devicePinCode = digits
            }
            if devicePinCode != oldValue {
                pinCodePromptError = nil
            }
        }
    }
    @Published var isConnectedElsewhere = false
    @Published var connectedElsewhereName = ""
    @Published var isMultiplePumpsFound = false
    @Published private(set) var heardPumpNames: [String] = []

    private struct HeardPump {
        var name: String
        var peripheral: CBPeripheral?
        var step: UInt8?
    }

    private let log = TandemLogger(category: "TandemKitScanViewModel")
    private var pumpManager: TandemPumpManager?
    private var nextStep: () -> Void
    private var heardPumps: [String: HeardPump] = [:]
    private var heardOrder: [String] = []
    private var lockedPump: String?
    private var pendingLock: (pump: String, check: DispatchWorkItem)?
    var codeStepSettleInterval: TimeInterval = 2
    private var multiplePumpsUnannounced = false
    private var connectedCheckTimer: Timer?
    private var connectedCheckSilencedUntil = Date.distantPast
    static let connectedAlertSilenceInterval: TimeInterval = 10
    static let pairingCodeLength = 6

    var isPinCodeComplete: Bool {
        devicePinCode.count == Self.pairingCodeLength
    }

    /// The advertised name carries the model, as in "Tandem Mobi 994".
    var pinPromptHeading: String {
        String(format: String(
            localized: "Enter the PIN for %@:",
            comment: "Heading above the pairing code boxes (1: the pump's name, such as Tandem Mobi 994)"
        ), connectingTo ?? "Tandem Mobi")
    }

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
        cancelPendingLock()
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
        guard currentPhase == .mobiOnPad, !isConnectedElsewhere, !isMultiplePumpsFound,
              Date() >= connectedCheckSilencedUntil,
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
        presentNextAlert()
    }

    var connectedElsewhereMessage: String {
        String(format: String(
            localized: "The device %@ is currently connected to this phone. Please go to iOS Bluetooth Settings, tap %@ and choose Forget, then come back to this screen.",
            comment: "Pairing warning when the pump is already connected to the phone (1: pump name, 2: pump name)"
        ), connectedElsewhereName, connectedElsewhereName)
    }

    func multiplePumpsDismissed() {
        isMultiplePumpsFound = false
        presentNextAlert()
    }

    var multiplePumpsMessage: String {
        String(format: String(
            localized: "%@ are nearby. Only the pump you place on the charging pad and double-press will be paired.",
            comment: "Pairing notice when more than one pump is advertising (1: the pumps' names)"
        ), ListFormatter.localizedString(byJoining: heardPumpNames))
    }

    /// SwiftUI presents one alert at a time, and none over the code prompt's sheet.
    private func presentNextAlert() {
        guard !isMultiplePumpsFound, !isConnectedElsewhere, !isPromptingPincode, !isConnectionError else { return }
        if multiplePumpsUnannounced {
            multiplePumpsUnannounced = false
            isMultiplePumpsFound = true
        } else if lockedPump != nil, currentPhase != .pairing {
            isPromptingPincode = true
        }
    }

    /// Its last advert is from before the scan stopped, and the pump may have left its pairing state since.
    private func releaseLockedPump() {
        if let lockedPump {
            heardPumps[lockedPump]?.step = nil
        }
        lockedPump = nil
    }

    func cancelPinPrompt() {
        isPromptingPincode = false
        releaseLockedPump()
        devicePinCode = ""
        pinCodePromptError = nil

        // Restart scanning
        _ = pumpManager?.bluetooth.startScan(deviceScanDidUpdate)
    }

    func processPinPrompt() {
        guard isPinCodeComplete else {
            pinCodePromptError = String(
                localized: "Enter all 6 digits of the pairing code",
                comment: "Error when the pairing code has fewer than six digits"
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

        guard let peripheral = lockedPump.flatMap({ heardPumps[$0]?.peripheral }) else {
            releaseLockedPump()
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
            self.releaseLockedPump()
            self.devicePinCode = ""
            self.currentPhase = .doubleTap
        }
    }

    /// Scanning waits for the alert to be dismissed: the pump may already be showing its pairing
    /// state, and the code prompt can't be presented over the alert.
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
        let step = Self.advertisedPairingStep(name: device.name, advertisementData: device.advertisementData)
        let name = device.advertisementData?[CBAdvertisementDataLocalNameKey] as? String ?? device.name
        DispatchQueue.main.async {
            self.pumpHeard(device.bleIdentifier, name: name, step: step, peripheral: device.peripheral)
        }
    }

    /// Pairs only the pump that alone reaches the code step: the first pump a scan hears may be another
    /// one nearby, and following it ignored the one the user had picked up.
    func pumpHeard(_ identifier: String, name: String, step: UInt8?, peripheral: CBPeripheral? = nil) {
        guard lockedPump == nil else { return }

        if var pump = heardPumps[identifier] {
            if !name.isEmpty { pump.name = name }
            if let peripheral { pump.peripheral = peripheral }
            // Some of a pump's packets carry no manufacturer data, and say nothing about the step.
            if let step, step != pump.step {
                log.info("\(pump.name) (\(identifier)) advertises pairing step 0x\(String(step, radix: 16))")
                pump.step = step
            }
            heardPumps[identifier] = pump
        } else {
            let pump = HeardPump(name: name.isEmpty ? "Tandem Mobi" : name, peripheral: peripheral, step: step)
            if let step {
                log.info("Heard \(pump.name) (\(identifier)) advertising pairing step 0x\(String(step, radix: 16))")
            } else {
                log.info("Heard \(pump.name) (\(identifier))")
            }
            heardPumps[identifier] = pump
            heardOrder.append(identifier)
            if heardOrder.count > 1, !isMultiplePumpsFound {
                multiplePumpsUnannounced = true
            }
        }
        let names = heardOrder.compactMap { heardPumps[$0]?.name }
        if names != heardPumpNames { heardPumpNames = names }

        let ready = readyPumps
        let onPad = heardOrder.filter { heardPumps[$0]?.step == 0x11 }
        if !ready.isEmpty || !onPad.isEmpty {
            let found = ListFormatter.localizedString(byJoining: (ready.isEmpty ? onPad : ready).compactMap { heardPumps[$0]?.name })
            if connectingTo != found { connectingTo = found }
            if currentPhase != .doubleTap { currentPhase = .doubleTap }
        } else if currentPhase != .mobiOnPad {
            currentPhase = .mobiOnPad
        }

        if ready.count == 1 {
            if pendingLock?.pump != ready[0] { scheduleLock(onto: ready[0]) }
        } else {
            cancelPendingLock()
        }
        presentNextAlert()
    }

    private var readyPumps: [String] {
        heardOrder.filter { heardPumps[$0]?.step == 0x12 }
    }

    /// Adverts arrive one at a time, so the first pump to reach the code step always looks like the only
    /// one; the wait gives every other pump in range several adverts (about five a second each) to say otherwise.
    private func scheduleLock(onto identifier: String) {
        cancelPendingLock()
        let check = DispatchWorkItem { [weak self] in self?.lock(onto: identifier) }
        pendingLock = (identifier, check)
        DispatchQueue.main.asyncAfter(deadline: .now() + codeStepSettleInterval, execute: check)
    }

    private func cancelPendingLock() {
        pendingLock?.check.cancel()
        pendingLock = nil
    }

    private func lock(onto identifier: String) {
        pendingLock = nil
        guard lockedPump == nil, readyPumps == [identifier], let pump = heardPumps[identifier] else { return }
        log.info("\(pump.name) is ready for its pairing code")
        lockedPump = identifier
        connectingTo = pump.name
        stopScan()
        presentNextAlert()
    }
}
