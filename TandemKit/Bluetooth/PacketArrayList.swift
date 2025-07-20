import Foundation

/// Parses incoming packets from the pump and validates them.
/// This is a greatly simplified Swift port of PumpX2 `PacketArrayList`.
struct PacketArrayList {
    let expectedOpCode: UInt8
    let expectedCargoSize: UInt8
    let expectedTxId: UInt8
    let isSigned: Bool

    private var fullCargo = Data()
    private(set) var opCode: UInt8 = 0
    private var firstByteMod15: UInt8 = 0

    mutating func validatePacket(_ packet: Data) {
        guard packet.count >= 3 else { return }
        firstByteMod15 = packet[0]
        let txId = packet[1]
        opCode = packet[2]
        if txId != expectedTxId { throw UnexpectedTransactionIdError(expected: expectedTxId, actual: txId) }
        if opCode != expectedOpCode { throw UnexpectedOpCodeError(expected: expectedOpCode, actual: opCode) }
        fullCargo.append(packet.dropFirst(2))
    }

    func needsMorePacket() -> Bool {
        return firstByteMod15 != 0
    }

    func messageData() -> Data {
        var data = Data([expectedOpCode, expectedTxId, expectedCargoSize])
        data.append(fullCargo)
        return data
    }

    func validate(_ authKey: Data) -> Bool {
        var data = messageData()
        guard data.count >= 2 else { return false }
        let crc = CalculateCRC16(Data(data.dropLast(2)))
        let expected = data.suffix(2)
        if crc != expected { return false }
        if isSigned {
            guard data.count >= 20 else { return false }
            let msgData = data.dropLast(20)
            let expectedHmac = data.suffix(20)
            let mac = HmacSha1(data: msgData, key: authKey)
            return mac == expectedHmac
        }
        return true
    }

    struct UnexpectedOpCodeError: Error { let expected: UInt8; let actual: UInt8 }
    struct UnexpectedTransactionIdError: Error { let expected: UInt8; let actual: UInt8 }
}