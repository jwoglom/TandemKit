//
//  Packetize.swift
//  TandemKit
//
//  Created by James Woglom on 1/13/25.
//

import Foundation
import TandemCore

// Helper to chunk an array into fixed-size subarrays.
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

private let DEFAULT_MAX_CHUNK_SIZE = 18
private let CONTROL_MAX_CHUNK_SIZE = 40

private func determineMaxChunkSize(_ message: Message) -> Int {
    if type(of: message).props.characteristic == .CONTROL_CHARACTERISTICS && type(of: message).props.type == .Request {
        return CONTROL_MAX_CHUNK_SIZE
    }
    return DEFAULT_MAX_CHUNK_SIZE
}


@MainActor
public func Packetize(message: Message, authenticationKey: Data?, txId: UInt8, timeSinceReset: UInt32?, maxChunkSize: Int? = nil) throws -> [Packet] {
    var props = type(of: message).props
    var opCode = props.opCode
    var length = message.cargo.count
    var chunkSize = maxChunkSize ?? determineMaxChunkSize(message)
    if props.signed {
        length += 24
        chunkSize = max(chunkSize, CONTROL_MAX_CHUNK_SIZE)
    }
    var packet: Data = Bytes.combine(Data([opCode]), Data([txId]), Data([UInt8(length - 3)]), message.cargo)
    
    if props.modifiesInsulinDelivery && !PumpStateSupplier.actionsAffectingInsulinDeliveryEnabled() {
        throw ActionsAffectingInsulinDeliveryNotEnabled()
    }

    if props.signed {
        guard let authenticationKey = authenticationKey,
              let timeSinceReset = timeSinceReset
        else {
            throw PacketizeError.missingAuthenticationKey
        }

        let i = length - 20
        var messageData = Bytes.firstN(packet, i)
        let tsrBytes = Bytes.toUint32(timeSinceReset)
        messageData.replaceSubrange((length-24)..<(length-20), with: tsrBytes)

        let hmacedOutput = HmacSha1(data: messageData, key: authenticationKey)
        packet.replaceSubrange(0..<i, with: messageData)
        packet.replaceSubrange(i..<i+hmacedOutput.count, with: hmacedOutput)
    }
    
    var crc = CalculateCRC16(packet)
    var packetWithCrc = Bytes.combine(packet, crc)
    
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

public struct ActionsAffectingInsulinDeliveryNotEnabled: Error {}

public enum PacketizeError: Error {
    case missingAuthenticationKey
}
