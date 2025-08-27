#if canImport(CoreBluetooth)
//
//  BluetoothCmd.swift
//  TandemKit
//
//  Created by James Woglom on 1/13/25.
//

import CoreBluetooth

struct BluetoothCmd {
    let uuid: CBUUID
    let value: Data
}
#endif
