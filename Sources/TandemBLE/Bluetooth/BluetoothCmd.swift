//
//  BluetoothCmd.swift
//  TandemKit
//
//  Created by James Woglom on 1/13/25.
//

import CoreBluetooth
import Foundation

struct BluetoothCmd {
    let uuid: CBUUID
    let value: Data
}
