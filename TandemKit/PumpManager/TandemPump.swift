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


public class TandemPump {
    private let log = OSLog(category: "TandemPump")
    private let bluetoothManager = BluetoothManager()

    private var state: PumpState?
    private var appInstanceId = 1

    var pumpComm: PumpComm

    init(_ state: PumpState?) {
        self.state = state

        self.pumpComm = PumpComm(pumpState: state)
        self.bluetoothManager.delegate = self
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
}
