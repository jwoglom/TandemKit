import CoreBluetooth
import LoopKit
import SwiftUI

final class TandemKitTroubleshootConnectionViewModel: ObservableObject {
    private let log = TandemLogger(category: "TandemKitTroubleshootConnectionViewModel")
    private let pumpManager: TandemPumpManager?

    @Published var isConnected: Bool = false
    @Published var isAttemptingReconnect: Bool = false

    @Published var bluetoothStatusText: String = ""
    @Published var isBluetoothPoweredOn: Bool = false

    /// Description of the pump saved to this app, or nil when none is paired.
    @Published var savedPumpText: String?
    /// Whether iOS's Bluetooth stack still knows the saved peripheral (retrievable by UUID). A
    /// paired pump that iOS no longer recognizes usually means it was removed in iOS Settings.
    @Published var isSavedPumpKnownToSystem: Bool = false

    @Published var lastConnectedText: String = ""
    /// Outcome of the most recent manual reconnect attempt, shown until the next attempt.
    @Published var reconnectResultText: String?

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    init(pumpManager: TandemPumpManager?) {
        self.pumpManager = pumpManager
        refresh()

        pumpManager?.addStatusObserver(self, queue: .main)
    }

    deinit {
        pumpManager?.removeStatusObserver(self)
    }

    func refresh() {
        guard let pumpManager else {
            return
        }

        isConnected = pumpManager.state.isConnected

        let bluetoothState = pumpManager.bluetooth.manager?.state ?? .unknown
        isBluetoothPoweredOn = bluetoothState == .poweredOn
        bluetoothStatusText = Self.describe(bluetoothState)

        let pumpState = pumpManager.state.pumpState
        if let peripheralUuid = pumpState.peripheralUuid {
            var parts = ["Tandem Mobi"]
            if let serial = pumpState.pumpSerial {
                parts.append("SN \(serial)")
            }
            savedPumpText = parts.joined(separator: " · ")

            if let central = pumpManager.bluetooth.manager,
               isBluetoothPoweredOn,
               let identifier = UUID(uuidString: peripheralUuid)
            {
                isSavedPumpKnownToSystem = !central.retrievePeripherals(withIdentifiers: [identifier]).isEmpty
            } else {
                isSavedPumpKnownToSystem = false
            }
        } else {
            savedPumpText = nil
            isSavedPumpKnownToSystem = false
        }

        if let lastConnected = pumpManager.lastSync {
            lastConnectedText = dateFormatter.string(from: lastConnected)
        } else {
            lastConnectedText = String(localized: "Never", comment: "Shown when the pump has never connected")
        }
    }

    func attemptReconnect() {
        guard let pumpManager, !isAttemptingReconnect else {
            return
        }

        isAttemptingReconnect = true
        reconnectResultText = nil

        pumpManager.attemptReconnect { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                self.isAttemptingReconnect = false
                self.refresh()
                self.reconnectResultText = self.isConnected ?
                    String(localized: "Connected", comment: "Reconnect succeeded") :
                    String(
                        localized: "Still unable to connect. Try the steps below.",
                        comment: "Reconnect failed"
                    )
            }
        }
    }

    private static func describe(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn:
            return String(localized: "On", comment: "Bluetooth powered on")
        case .poweredOff:
            return String(localized: "Off", comment: "Bluetooth powered off")
        case .unauthorized:
            return String(localized: "Not authorized", comment: "Bluetooth unauthorized")
        case .unsupported:
            return String(localized: "Unsupported", comment: "Bluetooth unsupported")
        case .resetting:
            return String(localized: "Resetting", comment: "Bluetooth resetting")
        case .unknown:
            return String(localized: "Unknown", comment: "Bluetooth state unknown")
        @unknown default:
            return String(localized: "Unknown", comment: "Bluetooth state unknown")
        }
    }
}

extension TandemKitTroubleshootConnectionViewModel: PumpManagerStatusObserver {
    func pumpManager(
        _: any LoopKit.PumpManager,
        didUpdate _: LoopKit.PumpManagerStatus,
        oldStatus _: LoopKit.PumpManagerStatus
    ) {
        DispatchQueue.main.async {
            self.refresh()
        }
    }
}
