//
//  Packetize.swift
//  TandemKit
//
//  Created by James Woglom on 1/13/25.
//

// Helper to chunk an array into fixed-size subarrays.
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}


func Packetize(message: Message, authenticationKey: Data?, txId: UInt8, timeSinceReset: UInt32?) throws -> [Packet] {
    var props = type(of: message).props
    var opCode = props.opCode
    var length = message.cargo.count
    var chunkSize = 18
    if props.signed {
        length += 24
        chunkSize = 40
    }
    var packet: Data = Bytes.combine(Data(opCode), Data(txId), Data(length - 3), message.cargo)
    
    if props.signed {
        guard let authenticationKey = authenticationKey,
              let timeSinceReset = timeSinceReset
        else {
            throw PumpCommError.missingAuthenticationKey
        }

        var i = length - 20
        var messageData = Bytes.firstN(packet, i)
        var tsrBytes = Bytes.toUint32(timeSinceReset)
        messageData[length-24...length-20] = tsrBytes
        
        var hmacedOutput = HmacSha1(data: messageData, key: authenticationKey)
        packet[0...i] = messageData
        packet[i...i+hmacedOutput.count] = hmacedOutput
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
