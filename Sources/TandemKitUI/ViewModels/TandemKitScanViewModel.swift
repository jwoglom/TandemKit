import CoreBluetooth
import LoopKit
import SwiftUI
import TandemCore

struct ScanResultItem: Identifiable {
    let id = UUID()
    var name: String
    let bleIdentifier: String
}

class TandemKitScanViewModel: ObservableObject {
    @Published var scannedDevices: [ScanResultItem] = []
    @Published var isScanning = false
    @Published var isConnecting = false
    @Published var connectingTo: String?
    @Published var isPromptingPincode = false
    @Published var pinCodePromptError: String?
    @Published var isConnectionError = false
    @Published var connectionErrorMessage: String?

    @Published var devicePinCode = ""

    private let log = PumpLogger(label: "TandemKitScanViewModel")
    private var pumpManager: TandemPumpManager?
    private var nextStep: () -> Void
    private var foundDevices: [String: CBPeripheral] = [:]
    private var selectedPeripheral: CBPeripheral?

    init(_ pumpManager: TandemPumpManager? = nil, nextStep: @escaping () -> Void) {
        self.pumpManager = pumpManager
        self.nextStep = nextStep

        self.pumpManager?.addScanDeviceObserver(self, queue: .main)
        self.pumpManager?.tandemPump.startScanning()
        isScanning = true
    }

    func connect(_ item: ScanResultItem) {
        guard let device = foundDevices[item.bleIdentifier] else {
            log.error("No device found for \(item.bleIdentifier)")
            return
        }

        stopScan()
        selectedPeripheral = device
        connectingTo = item.name

        // Show PIN prompt
        isPromptingPincode = true
        isConnecting = true
    }

    func stopScan() {
        pumpManager?.tandemPump.disconnect()
        isScanning = false
    }

    func cancelPinPrompt() {
        isPromptingPincode = false
        isConnecting = false
        selectedPeripheral = nil
        devicePinCode = ""

        // Clear the target peripheral filter
        pumpManager?.setTargetPeripheral(nil)

        // Restart scanning
        pumpManager?.tandemPump.startScanning()
        isScanning = true
    }

    func processPinPrompt() {
        guard !devicePinCode.isEmpty else {
            pinCodePromptError = "Please enter a pairing code"
            return
        }

        isPromptingPincode = false

        guard let pumpManager = pumpManager else {
            isConnecting = false
            isConnectionError = true
            connectionErrorMessage = "Pump manager not initialized"
            return
        }

        guard let peripheral = selectedPeripheral else {
            isConnecting = false
            isConnectionError = true
            connectionErrorMessage = "No peripheral selected"
            return
        }

        #if canImport(UIKit)
            // Set the target peripheral so the manager only connects to this specific device
            pumpManager.setTargetPeripheral(peripheral.identifier)

            pumpManager.pairPump(with: devicePinCode) { result in
                DispatchQueue.main.async {
                    self.pairComplete(result)
                }
            }
        #else
            isConnecting = false
            isConnectionError = true
            connectionErrorMessage = "Pairing not supported on this platform"
        #endif
    }

    func pairComplete(_ result: Result<Void, Error>) {
        isConnecting = false

        // Clear the target peripheral filter
        pumpManager?.setTargetPeripheral(nil)

        switch result {
        case .success:
            log.info("Pairing successful")
            nextStep()

        case let .failure(error):
            log.error("Pairing failed: \(error.localizedDescription)")
            isConnectionError = true
            connectionErrorMessage = error.localizedDescription
            selectedPeripheral = nil
            devicePinCode = ""
        }
    }

    deinit {
        pumpManager?.removeScanDeviceObserver(self)
    }
}

extension TandemKitScanViewModel: StateObserver {
    func deviceScanDidUpdate(_ device: TandemPumpScan) {
        // Avoid duplicates
        guard !scannedDevices.contains(where: { $0.bleIdentifier == device.bleIdentifier }) else {
            return
        }

        scannedDevices.append(ScanResultItem(name: device.name, bleIdentifier: device.bleIdentifier))
        foundDevices[device.bleIdentifier] = device.peripheral
    }
}
