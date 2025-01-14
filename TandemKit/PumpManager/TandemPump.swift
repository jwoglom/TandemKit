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
    
    init(_ state: PumpState?) {
        self.state = state

        self.pumpComm = PumpComm(pumpState: state)
        self.bluetoothManager.delegate = self
    }

}
