import Foundation
import TandemCore

/**
 * Packet represents the raw byte string included within a single Bluetooth response packet
 *
 * A combination of Packet's sent over a Bluetooth characteristic by one end of the BT communication
 * represents one Message.
 */
public struct Packet {
    public let packetsRemaining: UInt8
    public let txId: UInt8
    public let internalCargo: Data

    public var build: Data {
        Bytes.combine(Data([packetsRemaining]), Data([txId]), internalCargo)
    }

    public func merge(newPacket: Packet) -> Packet {
        Packet(
            packetsRemaining: 1 + max(packetsRemaining, newPacket.packetsRemaining),
            txId: txId,
            internalCargo: Bytes.combine(internalCargo, newPacket.internalCargo)
        )
    }
}
