import CoreBluetooth
import Foundation
import TandemBLE
import TandemCore

public protocol TandemPumpDelegate: AnyObject {
    func tandemPump(_ pump: TandemPump, shouldConnect peripheral: CBPeripheral, advertisementData: [String: Any]?) -> Bool
    func tandemPump(_ pump: TandemPump, didCompleteConfiguration peripheralManager: PeripheralManager)
    func tandemPump(_ pump: TandemPump, didDisconnectWithError error: Error?)
    func tandemPump(
        _ pump: TandemPump,
        didDiscoverDevice peripheral: CBPeripheral,
        advertisementData: [String: Any]?,
        rssi: NSNumber
    )
}

public extension TandemPumpDelegate {
    func tandemPump(_: TandemPump, didDiscoverDevice _: CBPeripheral, advertisementData _: [String: Any]?, rssi _: NSNumber) {}
    func tandemPump(_: TandemPump, didDisconnectWithError _: Error?) {}
}

public class TandemPump {
    private let log = TandemLogger(category: "TandemPump")
    private let bluetoothManager = BluetoothManager()

    private var appInstanceId = 1
    private var currentTxId: UInt8 = 0

    weak var delegate: TandemPumpDelegate?

    var pumpComm: PumpComm

    init(pumpState: PumpState?) {
        pumpComm = PumpComm(pumpState: pumpState)
        bluetoothManager.delegate = self
    }

    /// Start scanning for a Tandem pump peripheral.
    public func startScanning() {
        bluetoothManager.scanForPeripheral()
    }

    /// Start scanning for a Tandem pump peripheral.
    public func stopScanning() {
        bluetoothManager.stopScan()
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

    // when we have connected via bluetooth LE transport to the pump but we are not necessarily paired
    @MainActor func onPumpConnected(_ manager: PeripheralManager) {
        // Startup requests are now handled via the transport to maintain proper txId sequencing.
        log.info("Pump connected - completing configuration")
        delegate?.tandemPump(self, didCompleteConfiguration: manager)
    }

    @MainActor private func sendDefaultStartupRequests(_ manager: PeripheralManager) {
        log.info("Sending default startup requests")

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

    @MainActor public func sendCommand(_ message: Message, using manager: PeripheralManager) {
        send(message, via: manager)
    }

    @MainActor private func send(_ message: Message, via manager: PeripheralManager) {
        let wrapper = TronMessageWrapper(message: message, currentTxId: currentTxId)
        currentTxId = currentTxId &+ 1
        let targetCharacteristic = type(of: message).props.characteristic

        manager.perform { peripheralManager in
            let result = peripheralManager.sendMessagePackets(wrapper.packets, characteristic: targetCharacteristic)
            switch result {
            case .sentWithAcknowledgment:
                self.log.info("Message sent successfully: \(message)")
            case let .sentWithError(error):
                self.log.error("Message sent with error: \(error)")
            case let .unsentWithError(error):
                self.log.error("Message failed to send: \(error)")
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
        DispatchQueue.main.async {
            if let error {
                self.delegate?.tandemPump(self, didDisconnectWithError: error)
            } else {
                self.onPumpConnected(peripheralManager)
            }
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
        // don't automatically connect if no delegate
        return false
    }

    public func bluetoothManager(
        _: BluetoothManager,
        didCompleteConfiguration peripheralManager: PeripheralManager
    ) {
        delegate?.tandemPump(self, didCompleteConfiguration: peripheralManager)
    }

    public func bluetoothManager(
        _: BluetoothManager,
        didDiscoverDevice peripheral: CBPeripheral,
        advertisementData: [String: Any]?,
        rssi: NSNumber
    ) {
        delegate?.tandemPump(self, didDiscoverDevice: peripheral, advertisementData: advertisementData, rssi: rssi)
    }
}
