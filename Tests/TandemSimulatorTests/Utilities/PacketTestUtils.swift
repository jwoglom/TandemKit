import Foundation
import TandemCore

/// Utilities for building and parsing packets in tests
struct PacketTestUtils {
    // MARK: - Packet Building

    /// Build a simple request packet (single packet, no HMAC)
    /// - Parameters:
    ///   - opCode: Message opCode
    ///   - txId: Transaction ID
    ///   - cargo: Message cargo bytes
    /// - Returns: Complete packet data ready to send
    static func buildRequestPacket(
        opCode: UInt8,
        txId: UInt8,
        cargo: Data = Data()
    ) -> Data {
        var payload = cargo

        // Add CRC16
        let crc = cargo.crc16()
        payload.append(crc)

        // Build packet header
        var packet = Data()
        packet.append(0) // packetsRemaining = 0 (single packet)
        packet.append(txId) // packetTxId
        packet.append(opCode) // opCode
        packet.append(txId) // messageTxId
        packet.append(UInt8(cargo.count)) // declared payload length
        packet.append(payload)

        return packet
    }

    /// Build a signed request packet (with HMAC)
    /// - Parameters:
    ///   - opCode: Message opCode
    ///   - txId: Transaction ID
    ///   - cargo: Message cargo bytes
    ///   - derivedSecret: Derived secret for HMAC
    ///   - timeSinceReset: Pump time since reset
    /// - Returns: Complete signed packet data
    static func buildSignedRequestPacket(
        opCode: UInt8,
        txId: UInt8,
        cargo: Data = Data(),
        derivedSecret: Data,
        timeSinceReset: UInt32
    ) -> Data {
        // Build data to sign: [opCode] + [txId] + [timeSinceReset] + [cargo]
        var signedData = Data()
        signedData.append(opCode)
        signedData.append(txId)
        signedData.append(contentsOf: withUnsafeBytes(of: timeSinceReset.littleEndian) { Data($0) })
        signedData.append(cargo)

        // Calculate HMAC
        let hmac = signedData.hmacSHA1(key: derivedSecret)

        // Build payload: [cargo] + [CRC16] + [HMAC]
        var payload = cargo
        let crc = cargo.crc16()
        payload.append(crc)
        payload.append(hmac)

        // Build packet header
        var packet = Data()
        packet.append(0) // packetsRemaining = 0 (single packet)
        packet.append(txId) // packetTxId
        packet.append(opCode) // opCode
        packet.append(txId) // messageTxId
        packet.append(UInt8(cargo.count)) // declared payload length
        packet.append(payload)

        return packet
    }

    // MARK: - Packet Parsing

    /// Parse response packet(s) into message
    /// - Parameters:
    ///   - packets: Array of packet data (usually just one for simple responses)
    /// - Returns: Parsed response information
    static func parseResponsePackets(_ packets: [Data]) throws -> ParsedResponse {
        guard let firstPacket = packets.first else {
            throw PacketTestError.noPackets
        }

        // Parse header
        guard firstPacket.count >= 5 else {
            throw PacketTestError.packetTooShort
        }

        let packetsRemaining = firstPacket[0]
        let packetTxId = firstPacket[1]
        let opCode = firstPacket[2]
        let messageTxId = firstPacket[3]
        let declaredLength = Int(firstPacket[4])

        // Verify packet count
        let expectedPackets = Int(packetsRemaining) + 1
        guard packets.count == expectedPackets else {
            throw PacketTestError.packetCountMismatch(expected: expectedPackets, actual: packets.count)
        }

        // Extract payload from first packet
        var payload = Data(firstPacket.dropFirst(5))

        // Append payload from subsequent packets
        for packet in packets.dropFirst() {
            guard packet.count > 2 else {
                throw PacketTestError.packetTooShort
            }
            payload.append(packet.dropFirst(2))
        }

        // Extract CRC (last 2 bytes of cargo+crc)
        guard payload.count >= 2 else {
            throw PacketTestError.payloadTooShort
        }

        let crc = payload.suffix(2)
        let cargo = Data(payload.dropLast(2))

        // Validate CRC
        let calculatedCRC = cargo.crc16()
        guard crc == calculatedCRC else {
            throw PacketTestError.crcMismatch
        }

        return ParsedResponse(
            opCode: opCode,
            txId: messageTxId,
            cargo: cargo,
            declaredLength: declaredLength
        )
    }

    /// Parse a single response packet (convenience method)
    static func parseResponsePacket(_ packet: Data) throws -> ParsedResponse {
        try parseResponsePackets([packet])
    }
}

// MARK: - Supporting Types

struct ParsedResponse {
    let opCode: UInt8
    let txId: UInt8
    let cargo: Data
    let declaredLength: Int
}

enum PacketTestError: Error, LocalizedError {
    case noPackets
    case packetTooShort
    case packetCountMismatch(expected: Int, actual: Int)
    case payloadTooShort
    case crcMismatch

    var errorDescription: String? {
        switch self {
        case .noPackets:
            return "No packets provided"
        case .packetTooShort:
            return "Packet too short"
        case let .packetCountMismatch(expected, actual):
            return "Packet count mismatch: expected \(expected), got \(actual)"
        case .payloadTooShort:
            return "Payload too short"
        case .crcMismatch:
            return "CRC validation failed"
        }
    }
}

// MARK: - Message Building Helpers

extension PacketTestUtils {
    /// Build a TimeSinceResetRequest packet
    static func buildTimeSinceResetRequest(txId: UInt8 = 1) -> Data {
        guard let metadata = MessageRegistry.metadata(forName: "TimeSinceResetRequest") else {
            fatalError("TimeSinceResetRequest not found in registry")
        }

        // TimeSinceResetRequest has no cargo
        return buildRequestPacket(opCode: metadata.opCode, txId: txId, cargo: Data())
    }

    /// Build a HomeScreenMirrorRequest packet
    static func buildHomeScreenMirrorRequest(txId: UInt8 = 1) -> Data {
        guard let metadata = MessageRegistry.metadata(forName: "HomeScreenMirrorRequest") else {
            fatalError("HomeScreenMirrorRequest not found in registry")
        }

        // HomeScreenMirrorRequest has no cargo
        return buildRequestPacket(opCode: metadata.opCode, txId: txId, cargo: Data())
    }
}
