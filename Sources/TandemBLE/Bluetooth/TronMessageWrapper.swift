import Foundation
import TandemCore

/// Wraps a pump `Message` and provides the packetized data for transmission.
/// Mirrors the behavior of PumpX2 `TronMessageWrapper`.
struct TronMessageWrapper {
    let message: Message
    let packets: [Packet]

    @MainActor
    init(message: Message, currentTxId: UInt8) {
        self.message = message
        var authKey = Data()
        if type(of: message).props.signed {
            authKey = PumpStateSupplier.authenticationKey()
        } else {
            // Attempt to fetch a key if available
            authKey = PumpStateSupplier.authenticationKey()
        }
        self.packets = try! Packetize(message: message,
                                      authenticationKey: authKey,
                                      txId: currentTxId,
                                      timeSinceReset: PumpStateSupplier.pumpTimeSinceReset?())
    }

    @MainActor
    init(message: Message, currentTxId: UInt8, maxChunkSize: Int) {
        self.message = message
        var authKey = Data()
        if type(of: message).props.signed {
            authKey = PumpStateSupplier.authenticationKey()
        } else {
            authKey = PumpStateSupplier.authenticationKey()
        }
        self.packets = try! Packetize(message: message,
                                      authenticationKey: authKey,
                                      txId: currentTxId,
                                      timeSinceReset: PumpStateSupplier.pumpTimeSinceReset?(),
                                      maxChunkSize: maxChunkSize)
    }

    func buildPacketArrayList(_ messageType: MessageType) -> PacketArrayList {
        let props = type(of: message).props
        var opCode = props.opCode
        var size = props.size
        if messageType == .Response {
            opCode = props.opCode
            size = props.size
        } else {
            if props.signed { size += 24 }
        }
        return PacketArrayList(expectedOpCode: opCode,
                               expectedCargoSize: size,
                               expectedTxId: packets.first?.txId ?? 0,
                               isSigned: props.signed)
    }

    func mergeIntoSinglePacket() -> Packet? {
        var packet: Packet?
        for pkt in packets {
            if let existing = packet {
                packet = existing.merge(newPacket: pkt)
            } else {
                packet = pkt
            }
        }
        return packet
    }
}
