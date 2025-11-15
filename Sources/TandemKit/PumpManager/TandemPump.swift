import CoreBluetooth
import Foundation
import TandemBLE
import TandemCore
#if canImport(os)
    import os
#endif

public protocol TandemPumpDelegate: AnyObject {
    func tandemPump(_ pump: TandemPump, shouldConnect peripheral: CBPeripheral, advertisementData: [String: Any]?) -> Bool
    func tandemPump(_ pump: TandemPump, didCompleteConfiguration peripheralManager: PeripheralManager)
}

public class TandemPump {
    private let log = OSLog(category: "TandemPump")
    private let bluetoothManager = BluetoothManager()

    private var state: PumpState?
    private var appInstanceId = 1
    private var currentTxId: UInt8 = 0

    weak var delegate: TandemPumpDelegate?

    var pumpComm: PumpComm

    init(_ state: PumpState?) {
        self.state = state
        pumpComm = PumpComm(pumpState: state)
        bluetoothManager.delegate = self
    }

    /// Start scanning for a Tandem pump peripheral.
    public func startScanning() {
        bluetoothManager.scanForPeripheral()
    }

    /// Permanently disconnect from the pump.
    public func disconnect() {
        bluetoothManager.permanentDisconnect()
    }

    // MARK: - Configuration helpers

    func enableActionsAffectingInsulinDelivery() {
        PumpStateSupplier.enableActionsAffectingInsulinDelivery()
    }

    func enableTconnectAppConnectionSharing() {
        PumpStateSupplier.enableTconnectAppConnectionSharing()
    }

    func enableSendSharedConnectionResponseMessages() {
        PumpStateSupplier.enableSendSharedConnectionResponseMessages()
    }

    func relyOnConnectionSharingForAuthentication() {
        PumpStateSupplier.enableRelyOnConnectionSharingForAuthentication()
    }

    func onlySnoopBluetoothAndBlockAllPumpX2Functionality() {
        PumpStateSupplier.enableOnlySnoopBluetooth()
    }

    func configureDeliveryActions(enabled: Bool) {
        if enabled {
            PumpStateSupplier.enableActionsAffectingInsulinDelivery()
        } else {
            PumpStateSupplier.disableActionsAffectingInsulinDelivery()
        }
    }

    func configureConnectionSharing(enabled: Bool) {
        PumpStateSupplier.setConnectionSharingEnabled(enabled)
    }

    func setAppInstanceId(_ id: Int) {
        appInstanceId = id
    }

    // MARK: - Bluetooth events

    @MainActor  func onPumpConnected(_ manager: PeripheralManager) {
        sendDefaultStartupRequests(manager)
    }

    @MainActor  private func sendDefaultStartupRequests(_ manager: PeripheralManager) {
        log.default("Sending default startup requests")

        // Send initial status requests that Loop/Trio need
        let startupMessages: [Message] = [
            ApiVersionRequest(),
            PumpVersionRequest(),
            CurrentBatteryV2Request(),
            InsulinStatusRequest(),
            CurrentBasalStatusRequest(),
            CurrentBolusStatusRequest()
        ]

        for message in startupMessages {
            send(message, via: manager)
        }
    }

    @MainActor  public func sendCommand(_ message: Message, using manager: PeripheralManager) {
        send(message, via: manager)
    }

    @MainActor  private func send(_ message: Message, via manager: PeripheralManager) {
        let wrapper = TronMessageWrapper(message: message, currentTxId: currentTxId)
        currentTxId = currentTxId &+ 1
        let targetCharacteristic = type(of: message).props.characteristic

        manager.perform { peripheralManager in
            let result = peripheralManager.sendMessagePackets(wrapper.packets, characteristic: targetCharacteristic)
            switch result {
            case .sentWithAcknowledgment:
                self.log.default("Message sent successfully: %{public}@", String(describing: message))
            case let .sentWithError(error):
                self.log.error("Message sent with error: %{public}@", String(describing: error))
            case let .unsentWithError(error):
                self.log.error("Message failed to send: %{public}@", String(describing: error))
            }
        }
    }
}

extension TandemPump: BluetoothManagerDelegate {
    public func bluetoothManager(
        _: BluetoothManager,
        peripheralManager: PeripheralManager,
        isReadyWithError error: Error?
    ) {
        guard error == nil else { return }
        DispatchQueue.main.async {
            self.onPumpConnected(peripheralManager)
        }
    }

    public func bluetoothManager(
        _: BluetoothManager,
        shouldConnectPeripheral peripheral: CBPeripheral,
        advertisementData: [String: Any]?
    ) -> Bool {
        if let delegate = delegate {
            return delegate.tandemPump(self, shouldConnect: peripheral, advertisementData: advertisementData)
        }
        return true
    }

    public func bluetoothManager(
        _: BluetoothManager,
        didCompleteConfiguration peripheralManager: PeripheralManager
    ) {
        delegate?.tandemPump(self, didCompleteConfiguration: peripheralManager)
    }
}
