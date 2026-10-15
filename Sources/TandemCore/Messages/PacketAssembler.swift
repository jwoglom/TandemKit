import Foundation

/// A message as the pump framed it, its CRC and declared length checked.
struct AssembledMessage: Equatable {
    let opCode: UInt8
    let txId: UInt8
    /// The length byte of the header: cargo, plus the 24-byte trailer on a signed message.
    let payloadLength: Int
    /// Everything after the header, the CRC included, as message parsers have always been handed it.
    let cargo: Data
}

/// Reassembles one message from the notifications that carry it. Each notification is
/// `[remaining][txId]` and then a piece of `[opCode][txId][length][payload][CRC16]`: `remaining`, in
/// the low nibble, counts down to 0 on the last piece, and the txId is at byte 1 of every piece and
/// at byte 3 of the first. Only the next piece of the message under way is taken, so a piece of
/// another message cannot be spliced into it.
struct PacketAssembler {
    enum Step: Equatable {
        /// Neither the start of a message nor the next piece of this one; nothing was taken.
        case notPart
        case needsMore
        case complete(AssembledMessage)
        /// The last piece arrived, but the pieces do not make the message their header declares.
        case corrupt(String)
    }

    private var bytes: Data?
    private var txId: UInt8 = 0
    private var nextRemaining: UInt8 = 0

    var isEmpty: Bool { bytes == nil }

    /// The txId and opcode of `packet` if it can be the first piece of a message.
    static func start(of packet: Data) -> (txId: UInt8, opCode: UInt8)? {
        let packet = Data(packet)
        guard packet.count >= 5, packet[1] == packet[3] else { return nil }
        return (packet[1], packet[2])
    }

    func continues(with packet: Data) -> Bool {
        let packet = Data(packet)
        return bytes != nil && packet.count >= 3 && packet[1] == txId && packet[0] & 0x0F == nextRemaining
    }

    /// Takes `packet` as the next piece of the message under way, or as the first of a new one when
    /// none is. A completed or corrupt message leaves the assembler empty.
    mutating func take(_ packet: Data) -> Step {
        let packet = Data(packet)
        if bytes == nil {
            guard Self.start(of: packet) != nil else { return .notPart }
            bytes = Data(packet.dropFirst(2))
            txId = packet[1]
        } else {
            guard continues(with: packet) else { return .notPart }
            bytes?.append(packet.dropFirst(2))
        }

        let remaining = packet[0] & 0x0F
        guard remaining == 0 else {
            nextRemaining = remaining - 1
            return .needsMore
        }
        let message = bytes ?? Data()
        reset()
        return Self.validate(message)
    }

    mutating func reset() {
        bytes = nil
    }

    private static func validate(_ message: Data) -> Step {
        let payloadLength = Int(message[2])
        let length = 3 + payloadLength
        guard message.count == length + 2 else {
            return .corrupt("\(message.count) bytes where its header declares \(length + 2)")
        }
        guard CalculateCRC16(message.prefix(length)) == message.suffix(2) else {
            return .corrupt("CRC does not match")
        }
        return .complete(AssembledMessage(
            opCode: message[0],
            txId: message[1],
            payloadLength: payloadLength,
            cargo: Data(message.dropFirst(3))
        ))
    }
}
