import Foundation
import TandemCore
import Logging

/// Assembles multi-packet messages from individual packet data
class PacketAssembler {
    private let logger = Logger(label: "TandemSimulator.PacketAssembler")

    /// Represents a packet header
    struct PacketHeader {
        let packetsRemaining: UInt8
        let packetTxId: UInt8
        let opCode: UInt8
        let messageTxId: UInt8
        let declaredPayloadLength: Int
    }

    /// Result of packet assembly
    struct AssembledMessage {
        let opCode: UInt8
        let txId: UInt8
        let cargo: Data
        let isSigned: Bool
        let hmacSignature: Data?
    }

    /// Parse header from the first packet
    func parseHeader(from data: Data) throws -> PacketHeader {
        guard data.count >= 5 else {
            throw PacketAssemblerError.packetTooShort(expected: 5, actual: data.count)
        }

        let packetsRemaining = data[0]
        let packetTxId = data[1]
        let opCode = data[2]
        let messageTxId = data[3]
        let declaredLength = Int(data[4])

        return PacketHeader(
            packetsRemaining: packetsRemaining,
            packetTxId: packetTxId,
            opCode: opCode,
            messageTxId: messageTxId,
            declaredPayloadLength: declaredLength
        )
    }

    /// Assemble a complete message from packet(s)
    /// - Parameters:
    ///   - packets: Array of packet data (in order)
    ///   - characteristic: The characteristic the message was received on
    /// - Returns: Assembled message with cargo extracted
    func assemble(packets: [Data], characteristic: CharacteristicUUID) throws -> AssembledMessage {
        guard let firstPacket = packets.first else {
            throw PacketAssemblerError.noPackets
        }

        // Parse header from first packet
        let header = try parseHeader(from: firstPacket)

        logger.debug("Assembling message: opCode=\(header.opCode) txId=\(header.messageTxId) packets=\(packets.count)")

        // Verify packet count matches
        let expectedPackets = Int(header.packetsRemaining) + 1
        guard packets.count == expectedPackets else {
            throw PacketAssemblerError.packetCountMismatch(
                expected: expectedPackets,
                actual: packets.count
            )
        }

        // Extract payload from first packet (skip 5-byte header)
        guard firstPacket.count > 5 else {
            throw PacketAssemblerError.packetTooShort(expected: 6, actual: firstPacket.count)
        }

        var payload = Data(firstPacket.dropFirst(5))

        // Append payload from subsequent packets
        for (index, packet) in packets.dropFirst().enumerated() {
            // Subsequent packets have 2-byte header: packetsRemaining + txId
            guard packet.count > 2 else {
                throw PacketAssemblerError.packetTooShort(expected: 3, actual: packet.count)
            }

            // Verify packetsRemaining is decreasing
            let packetsRemaining = packet[0]
            let expectedRemaining = UInt8(header.packetsRemaining) - UInt8(index + 1)
            if packetsRemaining != expectedRemaining {
                logger.warning("Packet \(index + 1) has unexpected packetsRemaining: \(packetsRemaining) (expected \(expectedRemaining))")
            }

            payload.append(packet.dropFirst(2))
        }

        // Payload should contain: [cargo bytes] + [2-byte CRC16] + [optional 20-byte HMAC]
        guard payload.count >= 2 else {
            throw PacketAssemblerError.payloadTooShort(actual: payload.count)
        }

        // Check if message is signed (has HMAC)
        let isSigned = payload.count >= 22 // At minimum: 0 cargo + 2 CRC + 20 HMAC

        var hmacSignature: Data?
        var cargoAndCrc = payload

        if isSigned && payload.count >= 22 {
            // Last 20 bytes might be HMAC
            let possibleHmac = payload.suffix(20)
            let possibleCargoAndCrc = Data(payload.dropLast(20))

            // We'll assume it's signed if payload is long enough
            // The actual validation happens later with the derived secret
            hmacSignature = possibleHmac
            cargoAndCrc = possibleCargoAndCrc

            logger.debug("Message appears to be signed (HMAC: \(possibleHmac.hexadecimalString.prefix(16))...)")
        }

        // Extract CRC (last 2 bytes of cargo+crc)
        guard cargoAndCrc.count >= 2 else {
            throw PacketAssemblerError.payloadTooShort(actual: cargoAndCrc.count)
        }

        let crc = cargoAndCrc.suffix(2)
        let cargo = Data(cargoAndCrc.dropLast(2))

        // Validate CRC16
        let calculatedCRC = cargo.crc16()
        guard crc == calculatedCRC else {
            logger.error("CRC mismatch: expected \(calculatedCRC.hexadecimalString), got \(crc.hexadecimalString)")
            throw PacketAssemblerError.crcMismatch(
                expected: calculatedCRC,
                actual: crc
            )
        }

        logger.debug("Message assembled successfully: cargo=\(cargo.count) bytes, signed=\(isSigned)")

        return AssembledMessage(
            opCode: header.opCode,
            txId: header.messageTxId,
            cargo: cargo,
            isSigned: isSigned,
            hmacSignature: hmacSignature
        )
    }

    /// Validate HMAC signature if present
    func validateHMAC(
        message: AssembledMessage,
        timeSinceReset: UInt32,
        derivedSecret: Data
    ) throws {
        guard let hmac = message.hmacSignature else {
            // Not a signed message
            return
        }

        logger.debug("Validating HMAC signature")

        // Reconstruct the data that was signed
        // Format: [opCode] + [txId] + [timeSinceReset (4 bytes)] + [cargo]
        var signedData = Data()
        signedData.append(message.opCode)
        signedData.append(message.txId)
        signedData.append(contentsOf: withUnsafeBytes(of: timeSinceReset.littleEndian) { Data($0) })
        signedData.append(message.cargo)

        // Calculate expected HMAC
        let calculatedHMAC = signedData.hmacSHA1(key: derivedSecret)

        guard hmac == calculatedHMAC else {
            logger.error("HMAC validation failed")
            logger.debug("Expected: \(calculatedHMAC.hexadecimalString)")
            logger.debug("Got: \(hmac.hexadecimalString)")
            throw PacketAssemblerError.hmacMismatch
        }

        logger.debug("HMAC validation successful")
    }
}

// MARK: - Errors

enum PacketAssemblerError: Error, LocalizedError {
    case noPackets
    case packetTooShort(expected: Int, actual: Int)
    case packetCountMismatch(expected: Int, actual: Int)
    case payloadTooShort(actual: Int)
    case crcMismatch(expected: Data, actual: Data)
    case hmacMismatch

    var errorDescription: String? {
        switch self {
        case .noPackets:
            return "No packets provided for assembly"
        case .packetTooShort(let expected, let actual):
            return "Packet too short: expected at least \(expected) bytes, got \(actual)"
        case .packetCountMismatch(let expected, let actual):
            return "Packet count mismatch: expected \(expected), got \(actual)"
        case .payloadTooShort(let actual):
            return "Payload too short: got \(actual) bytes"
        case .crcMismatch(let expected, let actual):
            return "CRC mismatch: expected \(expected.hexadecimalString), got \(actual.hexadecimalString)"
        case .hmacMismatch:
            return "HMAC validation failed"
        }
    }
}
