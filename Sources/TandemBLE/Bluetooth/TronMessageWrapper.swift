import Foundation
import TandemCore

/// Wraps a pump `Message` and provides the packetized data for transmission.
/// Mirrors the behavior of PumpX2 `TronMessageWrapper`.
public struct TronMessageWrapper {
    public let message: Message
    public let packets: [Packet]

    @MainActor
    public init(message: Message, currentTxId: UInt8) {
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
    public init(message: Message, currentTxId: UInt8, maxChunkSize: Int) {
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
        let requestProps = type(of: message).props
        var opCode = requestProps.opCode
        var size = requestProps.size
        var isSigned = requestProps.signed

        if messageType == .Response {
            if let responseMeta = TronMessageWrapper.responseMetadata(for: message) {
                opCode = responseMeta.opCode
                size = UInt8(truncatingIfNeeded: responseMeta.size)
                isSigned = responseMeta.signed
            }
        } else if requestProps.signed {
            size &+= 24
        }

        return PacketArrayList(expectedOpCode: opCode,
                               expectedCargoSize: size,
                               expectedTxId: packets.first?.txId ?? 0,
                               isSigned: isSigned)
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

    private static func responseMetadata(for message: Message) -> MessageMetadata? {
        let requestTypeName = String(describing: type(of: message))
        if let meta = MessageRegistry.metadata(forName: requestTypeName) {
            if meta.messageType == .Response {
                return meta
            }
        }

        if requestTypeName.hasSuffix("Request") {
            let base = requestTypeName.dropLast("Request".count)
            let responseName = base + "Response"
            if let meta = MessageRegistry.metadata(forName: String(responseName)) {
                return meta
            }
        }

        let fallback = requestTypeName + "Response"
        return MessageRegistry.metadata(forName: fallback)
    }
}
