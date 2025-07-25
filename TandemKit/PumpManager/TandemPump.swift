//
//  TandemPump.swift
//  TandemKit
//
//  Created by James Woglom on 1/5/25.
//


import Foundation
import CoreBluetooth
import LoopKit
import OSLog

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
        PumpStateSupplier.relyOnConnectionSharingForAuthentication()
    }

    func onlySnoopBluetoothAndBlockAllPumpX2Functionality() {
        PumpStateSupplier.enableOnlySnoopBluetooth()
    }

    func setAppInstanceId(_ id: Int) {
        self.appInstanceId = id
    }

}

extension TandemPump: BluetoothManagerDelegate {
    func bluetoothManager(_ manager: BluetoothManager, peripheralManager: PeripheralManager, isReadyWithError error: Error?) {
        // No-op in this simplified port
    }

    func bluetoothManager(_ manager: BluetoothManager, shouldConnectPeripheral peripheral: CBPeripheral, advertisementData: [String : Any]?) -> Bool {
        return true
    }

    func bluetoothManager(_ manager: BluetoothManager, didCompleteConfiguration peripheralManager: PeripheralManager) {
        // Intentionally left blank
    }
    // MARK: - Bluetooth events

    func onPumpConnected(_ manager: PeripheralManager) {
        sendDefaultStartupRequests(manager)
    }

    private func sendDefaultStartupRequests(_ manager: PeripheralManager) {
        let apiReq = ApiVersionRequest(cargo: Data())
        let tsrReq = TimeSinceResetRequest(cargo: Data())
        let requests: [Message] = [apiReq, tsrReq]
        for req in requests {
            send(req, via: manager)
        }
    }

    public func sendCommand(_ message: Message, using manager: PeripheralManager) {
        send(message, via: manager)
    }

    private func send(_ message: Message, via manager: PeripheralManager) {
        let wrapper = TronMessageWrapper(message: message, currentTxId: currentTxId)
        currentTxId &+= 1
        manager.perform { pm in
            _ = pm.sendMessagePackets(wrapper.packets)
        }
    }

}

extension TandemPump: BluetoothManagerDelegate {
    func bluetoothManager(_ manager: BluetoothManager, peripheralManager: PeripheralManager, isReadyWithError error: Error?) {
        guard error == nil else { return }
        onPumpConnected(peripheralManager)
    }

    func bluetoothManager(_ manager: BluetoothManager, shouldConnectPeripheral peripheral: CBPeripheral, advertisementData: [String : Any]?) -> Bool {
        if let delegate = delegate {
            return delegate.tandemPump(self, shouldConnect: peripheral, advertisementData: advertisementData)
        }
        return true
    }

    func bluetoothManager(_ manager: BluetoothManager, didCompleteConfiguration peripheralManager: PeripheralManager) {
        delegate?.tandemPump(self, didCompleteConfiguration: peripheralManager)
    }
}

