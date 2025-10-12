//
//  TandemPump.swift
//  TandemKit
//
//  Created by James Woglom on 1/5/25.
//

import Foundation
import CoreBluetooth
import TandemCore
import TandemBLE
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
        self.pumpComm = PumpComm(pumpState: state)
        self.bluetoothManager.delegate = self
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
        // TODO: Implement when PumpStateSupplier is available
        print("TandemPump: enableActionsAffectingInsulinDelivery() called")
    }

    func enableTconnectAppConnectionSharing() {
        // TODO: Implement when PumpStateSupplier is available
        print("TandemPump: enableTconnectAppConnectionSharing() called")
    }

    func enableSendSharedConnectionResponseMessages() {
        // TODO: Implement when PumpStateSupplier is available
        print("TandemPump: enableSendSharedConnectionResponseMessages() called")
    }

    func relyOnConnectionSharingForAuthentication() {
        // TODO: Implement when PumpStateSupplier is available
        print("TandemPump: relyOnConnectionSharingForAuthentication() called")
    }

    func onlySnoopBluetoothAndBlockAllPumpX2Functionality() {
        // TODO: Implement when PumpStateSupplier is available
        print("TandemPump: onlySnoopBluetoothAndBlockAllPumpX2Functionality() called")
    }

    func setAppInstanceId(_ id: Int) {
        self.appInstanceId = id
    }

    // MARK: - Bluetooth events

    @MainActor
    func onPumpConnected(_ manager: PeripheralManager) {
        sendDefaultStartupRequests(manager)
    }

    @MainActor
    private func sendDefaultStartupRequests(_ manager: PeripheralManager) {
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

    @MainActor
    public func sendCommand(_ message: Message, using manager: PeripheralManager) {
        send(message, via: manager)
    }

    @MainActor
    private func send(_ message: Message, via manager: PeripheralManager) {
        let wrapper = TronMessageWrapper(message: message, currentTxId: currentTxId)
        currentTxId = currentTxId &+ 1
        let targetCharacteristic = type(of: message).props.characteristic

        manager.perform { peripheralManager in
            let result = peripheralManager.sendMessagePackets(wrapper.packets, characteristic: targetCharacteristic)
            switch result {
            case .sentWithAcknowledgment:
                self.log.default("Message sent successfully: %{public}@", String(describing: message))
            case .sentWithError(let error):
                self.log.error("Message sent with error: %{public}@", String(describing: error))
            case .unsentWithError(let error):
                self.log.error("Message failed to send: %{public}@", String(describing: error))
            }
        }
    }
}

extension TandemPump: BluetoothManagerDelegate {
    public func bluetoothManager(_ manager: BluetoothManager,
                                  peripheralManager: PeripheralManager,
                                  isReadyWithError error: Error?) {
        guard error == nil else { return }
        DispatchQueue.main.async {
            self.onPumpConnected(peripheralManager)
        }
    }

    public func bluetoothManager(_ manager: BluetoothManager,
                                  shouldConnectPeripheral peripheral: CBPeripheral,
                                  advertisementData: [String : Any]?) -> Bool {
        if let delegate = delegate {
            return delegate.tandemPump(self, shouldConnect: peripheral, advertisementData: advertisementData)
        }
        return true
    }

    public func bluetoothManager(_ manager: BluetoothManager,
                                  didCompleteConfiguration peripheralManager: PeripheralManager) {
        delegate?.tandemPump(self, didCompleteConfiguration: peripheralManager)
    }
}
