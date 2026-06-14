import Foundation

enum Packetize {
    private static let logger = TandemLogger(category: "Packetize")
    private static let DEFAULT_MAX_CHUNK_SIZE = 18
    private static let CONTROL_MAX_CHUNK_SIZE = 40

    public static func parse(
        message: Message,
        authenticationKey: Data?,
        txId: UInt8,
        timeSinceReset: UInt32?,
        maxChunkSize: Int? = nil
    ) -> [Packet] {
        let props = type(of: message).props
        let opCode = props.opCode
        var chunkSize = maxChunkSize ?? determineMaxChunkSize(message)
        let basePayloadLength = message.cargo.count
        let payloadLength = basePayloadLength + (props.signed ? 24 : 0)

        guard payloadLength < 256 else {
            logger.error("Payload too large for single packet header")
            return []
        }

        var packet = Data()
        packet.append(opCode)
        packet.append(txId)
        packet.append(UInt8(payloadLength))
        packet.append(message.cargo)

        if props.signed {
            guard let authenticationKey = authenticationKey,
                  let timeSinceReset = timeSinceReset
            else {
                logger.error("missingAuthenticationKey")
                return []
            }

            packet.append(Data(repeating: 0, count: 24))
            chunkSize = max(chunkSize, CONTROL_MAX_CHUNK_SIZE)

            let hmacStartIndex = packet.count - 20
            var messageData = Bytes.firstN(packet, hmacStartIndex)
            let tsrBytes = Bytes.toUint32(timeSinceReset)
            let tsrRange = (messageData.count - 4) ..< messageData.count
            messageData.replaceSubrange(tsrRange, with: tsrBytes)

            let hmacedOutput = HmacSha1(data: messageData, key: authenticationKey)
            packet.replaceSubrange(0 ..< hmacStartIndex, with: messageData)
            packet.replaceSubrange(hmacStartIndex ..< hmacStartIndex + hmacedOutput.count, with: hmacedOutput)
        }

        let crc = CalculateCRC16(packet)
        let packetWithCrc = Bytes.combine(packet, crc)

        var packets: [Packet] = []
        let chunked = packetWithCrc.chunked(into: chunkSize)
        var b = chunked.count - 1
        for bytes in chunked {
            let packet = Packet(packetsRemaining: UInt8(b), txId: txId, internalCargo: bytes)
            packets.append(packet)
            b -= 1
        }

        return packets
    }

    private static func determineMaxChunkSize(_ message: Message) -> Int {
        if type(of: message).props.characteristic == CharacteristicUUID.CONTROL_CHARACTERISTICS,
           type(of: message).props.type == .Request
        {
            return Self.CONTROL_MAX_CHUNK_SIZE
        }

        return Self.DEFAULT_MAX_CHUNK_SIZE
    }
}

public struct Packet {
    public let packetsRemaining: UInt8
    public let txId: UInt8
    public let internalCargo: Data

    public func build() -> Data {
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

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
