import Foundation
import TandemCore
import Logging

/// Builds BLE packets from response messages
class PacketBuilder {
    private let logger = Logger(label: "TandemSimulator.PacketBuilder")

    /// Build packet(s) for a response message
    /// - Parameters:
    ///   - message: The message to send
    ///   - metadata: Message metadata
    ///   - txId: Transaction ID to use
    ///   - timeSinceReset: Pump time since reset (for HMAC)
    ///   - derivedSecret: Derived secret for HMAC signing (if needed)
    ///   - characteristic: The characteristic to send on
    /// - Returns: Array of packet data to send
    func build(
        message: Message,
        metadata: MessageMetadata,
        txId: UInt8,
        timeSinceReset: UInt32,
        derivedSecret: Data?,
        characteristic: CharacteristicUUID
    ) throws -> [Data] {
        let cargo = message.cargo

        logger.debug("Building packets for \(metadata.name): cargo=\(cargo.count) bytes, signed=\(metadata.signed)")

        // Build payload: [cargo] + [CRC16] + [optional HMAC]
        var payload = cargo

        // Add CRC16
        let crc = cargo.crc16()
        payload.append(crc)

        // Add HMAC if message is signed
        if metadata.signed {
            guard let secret = derivedSecret else {
                throw PacketBuilderError.missingDerivedSecret
            }

            // Build data to sign: [opCode] + [txId] + [timeSinceReset] + [cargo]
            var signedData = Data()
            signedData.append(metadata.opCode)
            signedData.append(txId)
            signedData.append(contentsOf: withUnsafeBytes(of: timeSinceReset.littleEndian) { Data($0) })
            signedData.append(cargo)

            let hmac = signedData.hmacSHA1(key: secret)
            payload.append(hmac)

            logger.debug("Added HMAC signature: \(hmac.hexadecimalString.prefix(16))...")
        }

        // Determine chunk size based on characteristic
        let maxChunkSize = chunkSize(for: characteristic)

        // Build packets
        var packets: [Data] = []
        var offset = 0
        var packetsRemaining = UInt8((payload.count + maxChunkSize - 1) / maxChunkSize)

        while offset < payload.count {
            packetsRemaining -= 1
            let chunkEnd = min(offset + maxChunkSize, payload.count)
            let chunk = payload[offset..<chunkEnd]

            var packet = Data()

            if packets.isEmpty {
                // First packet: [packetsRemaining] + [txId] + [opCode] + [txId] + [length] + [chunk]
                packet.append(packetsRemaining)
                packet.append(txId)
                packet.append(metadata.opCode)
                packet.append(txId)
                packet.append(UInt8(cargo.count))
                packet.append(chunk)
            } else {
                // Subsequent packets: [packetsRemaining] + [txId] + [chunk]
                packet.append(packetsRemaining)
                packet.append(txId)
                packet.append(chunk)
            }

            packets.append(packet)
            offset = chunkEnd
        }

        logger.debug("Built \(packets.count) packet(s) for \(metadata.name)")

        return packets
    }

    /// Get the chunk size for a characteristic
    private func chunkSize(for characteristic: CharacteristicUUID) -> Int {
        switch characteristic {
        case .CONTROL_CHARACTERISTICS, .CONTROL_STREAM_CHARACTERISTICS:
            return 40 // Control characteristics use larger chunks
        default:
            return 18 // Data characteristics use smaller chunks
        }
    }
}

// MARK: - Errors

enum PacketBuilderError: Error, LocalizedError {
    case missingDerivedSecret

    var errorDescription: String? {
        switch self {
        case .missingDerivedSecret:
            return "Message requires HMAC signing but no derived secret provided"
        }
    }
}
