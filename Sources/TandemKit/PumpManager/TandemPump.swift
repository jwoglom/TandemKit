//
//  TandemPump.swift
//  TandemKit
//
//  Created by James Woglom on 1/5/25.
//

import Foundation
import CoreBluetooth
import TandemCore
#if os(macOS)
import os
#endif

// Placeholder types for missing dependencies
public protocol PeripheralManager {
    func perform(_ block: @escaping (PeripheralManager) -> Void)
    func sendMessagePackets(_ packets: [Data]) -> Bool
}

public protocol BluetoothManagerDelegate: AnyObject {
    func bluetoothManager(_ manager: BluetoothManager, peripheralManager: PeripheralManager, isReadyWithError error: Error?)
    func bluetoothManager(_ manager: BluetoothManager, shouldConnectPeripheral peripheral: CBPeripheral, advertisementData: [String: Any]?) -> Bool
    func bluetoothManager(_ manager: BluetoothManager, didCompleteConfiguration peripheralManager: PeripheralManager)
}

public class BluetoothManager {
    weak var delegate: BluetoothManagerDelegate?
    
    func scanForPeripheral() {
        // TODO: Implement actual scanning
        print("BluetoothManager: scanForPeripheral() called")
    }
}

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

    func onPumpConnected(_ manager: PeripheralManager) {
        sendDefaultStartupRequests(manager)
    }

    private func sendDefaultStartupRequests(_ manager: PeripheralManager) {
        // TODO: Implement when Message types are available
        print("TandemPump: sendDefaultStartupRequests() called")
    }

    public func sendCommand(_ message: Message, using manager: PeripheralManager) {
        send(message, via: manager)
    }

    private func send(_ message: Message, via manager: PeripheralManager) {
        // TODO: Implement when TronMessageWrapper is available
        print("TandemPump: send() called")
    }
}

extension TandemPump: BluetoothManagerDelegate {
    public func bluetoothManager(_ manager: BluetoothManager, peripheralManager: PeripheralManager, isReadyWithError error: Error?) {
        guard error == nil else { return }
        onPumpConnected(peripheralManager)
    }

    public func bluetoothManager(_ manager: BluetoothManager, shouldConnectPeripheral peripheral: CBPeripheral, advertisementData: [String : Any]?) -> Bool {
        if let delegate = delegate {
            return delegate.tandemPump(self, shouldConnect: peripheral, advertisementData: advertisementData)
        }
        return true
    }

    public func bluetoothManager(_ manager: BluetoothManager, didCompleteConfiguration peripheralManager: PeripheralManager) {
        delegate?.tandemPump(self, didCompleteConfiguration: peripheralManager)
    }
}

