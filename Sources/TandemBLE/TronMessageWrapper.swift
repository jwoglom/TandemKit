import Foundation

private let tronLogger = TandemLogger(category: "TronMessageWrapper")

/// Wraps a pump `Message` and provides the packetized data for transmission.
/// Mirrors the behavior of PumpX2 `TronMessageWrapper`.
public struct TronMessageWrapper {
    public let message: Message
    public let requestMetadata: MessageMetadata
    public let responseMetadata: MessageMetadata?
    public let packets: [Packet]

    public init(message: Message, currentTxId: UInt8) {
        self.init(message: message, currentTxId: currentTxId, maxChunkSize: nil)
    }

    public init(message: Message, currentTxId: UInt8, maxChunkSize: Int?) {
        self.message = message

        // Get metadata for the message
        guard let reqMeta = MessageRegistry.metadata(for: message) else {
            fatalError("No metadata found for message type: \(String(describing: type(of: message)))")
        }
        requestMetadata = reqMeta
        responseMetadata = MessageRegistry.responseMetadata(for: message)

        let signed = type(of: message).props.signed
        var authKey = Data()
        if signed {
            authKey = PumpStateSupplier.authenticationKey()
        } else {
            authKey = Data() // empty byte array
        }

        let timeSinceReset = PumpStateSupplier.pumpTimeSinceReset?()
        let authKeyHex = authKey.map { String(format: "%02X", $0) }.joined()
        let authKeyDisplay = authKey.isEmpty ? "none" : "\(authKey.count) bytes [\(authKeyHex.prefix(16))...]"

        tronLogger.debug("[TronMessageWrapper]   signed: \(signed), authKey: \(authKeyDisplay)")
        tronLogger.debug("[TronMessageWrapper]   txId: \(currentTxId), timeSinceReset: \(String(describing: timeSinceReset))")

        packets = try! Packetize(
            message: message,
            authenticationKey: authKey,
            txId: currentTxId,
            timeSinceReset: timeSinceReset,
            maxChunkSize: maxChunkSize
        )
        tronLogger.debug("[TronMessageWrapper]   got packets: \(packets)")
    }

    func buildPacketArrayList(_ messageType: MessageType) -> PacketArrayList {
        let requestProps = type(of: message).props
        var opCode = requestProps.opCode
        var size = requestProps.size
        var isSigned = requestProps.signed

        if messageType == .Response {
            if let responseMeta = responseMetadata {
                tronLogger
                    .debug(
                        "[TronMessageWrapper] response metadata for \(type(of: message)) -> opCode=\(responseMeta.opCode) size=\(responseMeta.size)"
                    )
                opCode = responseMeta.opCode
                size = UInt8(truncatingIfNeeded: responseMeta.size)
                isSigned = responseMeta.signed
            } else {
                tronLogger.warning("[TronMessageWrapper] missing response metadata for \(type(of: message))")
            }
        } else if requestProps.signed {
            size &+= 24
        }

        return PacketArrayList(
            expectedOpCode: opCode,
            expectedCargoSize: size,
            expectedTxId: packets.first?.txId ?? 0,
            isSigned: isSigned,
            requestMetadata: requestMetadata,
            responseMetadata: responseMetadata
        )
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

    // MARK: - Convenience Methods

    /// Get the transaction ID for this wrapper
    public var txId: UInt8 {
        packets.first?.txId ?? 0
    }

    /// Get the response type expected for this request
    public func getResponseType() -> Message.Type? {
        responseMetadata?.type
    }

    /// Get the request message
    public func getRequest() -> Message {
        message
    }
}
