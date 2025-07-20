import Foundation

/// Wraps a pump `Message` and provides the packetized data for transmission.
/// Mirrors the behavior of PumpX2 `TronMessageWrapper`.
struct TronMessageWrapper {
    let message: Message
    let packets: [Packet]

    init(message: Message, currentTxId: UInt8, maxChunkSize: Int = 18) {
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

    func buildPacketArrayList(_ type: MessageType) -> PacketArrayList {
        let props = type(of: message).props
        var opCode = props.opCode
        var size = props.size
        if type == .Response {
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
}