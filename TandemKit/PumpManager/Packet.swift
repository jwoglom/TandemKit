//
//  Packet.swift
//  TandemKit
//
//  Created by James Woglom on 1/13/25.
//
// see messages/src/main/java/com/jwoglom/pumpx2/pump/messages/bluetooth/models/Packet.java

import CoreBluetooth

/**
 * Packet represents the raw byte string included within a single Bluetooth response packet
 *
 * A combination of Packet's sent over a Bluetooth characteristic by one end of the BT communication
 * represents one Message.
 */
struct Packet {
    let packetsRemaining: UInt8
    let txId: UInt8
    let internalCargo: Data
    
    public var build: Data {
        return Bytes.combine(Data(packetsRemaining), Data(txId), internalCargo)
    }
    
    public func merge(newPacket: Packet) -> Packet {
        return Packet(packetsRemaining: 1+max(packetsRemaining, newPacket.packetsRemaining), txId: txId, internalCargo: Bytes.combine(internalCargo, newPacket.internalCargo))
    }
}
