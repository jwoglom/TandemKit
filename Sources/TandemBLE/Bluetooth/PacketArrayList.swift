import Foundation
import TandemCore

private let packetArrayLogger = PumpLogger(label: "TandemBLE.PacketArrayList")

/// Parses incoming packets from the pump and validates them.
/// This mirrors the behaviour of PumpX2 `PacketArrayList`.
public struct PacketArrayList {
    static let IGNORE_INVALID_HMAC = "IGNORE_HMAC_SIGNATURE_EXCEPTION"
    static let ignoreInvalidTxId = false

    let expectedOpCode: UInt8
    private(set) var expectedCargoSize: UInt8
    let expectedTxId: UInt8
    let isSigned: Bool
    let requestMetadata: MessageMetadata?  // Context: the request that initiated this
    let responseMetadata: MessageMetadata?  // Context: the expected response

    private var actualExpectedCargoSize: Int
    private var fullCargo: Data
    private var messageDataBuffer: Data
    private(set) var opCode: UInt8 = 0
    private var firstByteMod15: Int = 0
    private var empty = true
    private var expectedCrc = Data(repeating: 0, count: 2)

    init(expectedOpCode: UInt8, expectedCargoSize: UInt8, expectedTxId: UInt8, isSigned: Bool,
         requestMetadata: MessageMetadata? = nil, responseMetadata: MessageMetadata? = nil) {
        self.expectedOpCode = expectedOpCode
        self.expectedCargoSize = expectedCargoSize
        let sizeInt = Int(Int8(bitPattern: expectedCargoSize))
        self.actualExpectedCargoSize = sizeInt >= 0 ? sizeInt : sizeInt + 256
        self.expectedTxId = expectedTxId
        self.isSigned = isSigned
        self.requestMetadata = requestMetadata
        self.responseMetadata = responseMetadata
        self.fullCargo = Data(repeating: 0, count: self.actualExpectedCargoSize + 2)
        self.messageDataBuffer = Data(repeating: 0, count: 3)
    }

    var debugFirstByteMod15: Int { firstByteMod15 }
    var expectedOpCodeValue: UInt8 { expectedOpCode }

    private mutating func parse(_ packet: Data) throws {
        let opCode = packet[2]
        var cargoSize = Int(Int8(bitPattern: packet[4]))
        if cargoSize < 0 { cargoSize += 256 }

        if opCode == expectedOpCode {
            firstByteMod15 = Int(packet[0] & 0x0f)
            let txId = packet[3]
            if txId != expectedTxId {
                if PacketArrayList.ignoreInvalidTxId { return }
                throw UnexpectedTransactionIdError(expected: expectedTxId, actual: txId)
            }
            if cargoSize != actualExpectedCargoSize {
                if cargoSize == actualExpectedCargoSize + 24 && isSigned {
                    expectedCargoSize &+= 24
                    actualExpectedCargoSize += 24
                } else {
                    throw InvalidCargoSizeError(expected: actualExpectedCargoSize, actual: cargoSize)
                }
            }
            fullCargo = Data(packet.dropFirst(5))
        } else {
            throw UnexpectedOpCodeError(expected: expectedOpCode, actual: opCode)
        }
        packetArrayLogger.debug("[PacketArrayList] parse ok opCode=\(opCode) firstByteMod15=\(firstByteMod15) cargoSize=\(cargoSize)")
    }

    mutating func validatePacket(_ packet: Data) throws {
        guard packet.count >= 3 else { throw InvalidDataSizeError() }
        let firstByte = packet[0]
        let txId = packet[1]
        let opCode = packet[2]
        if txId != expectedTxId {
            if PacketArrayList.ignoreInvalidTxId { return }
            throw UnexpectedTransactionIdError(expected: expectedTxId, actual: txId)
        }

        if empty {
            try parse(packet)
        } else if (firstByte & 0x0f) == 0 {
            if self.firstByteMod15 == 0 {
                fullCargo.append(packet.dropFirst(2))
            } else {
                throw InvalidPacketSequenceError()
            }
        } else if self.firstByteMod15 == Int(firstByte & 0x0f) {
            fullCargo.append(packet.dropFirst(2))
        } else {
            throw InvalidPacketSequenceError()
        }

        empty = false
        self.firstByteMod15 = Int(firstByte & 0x0f) - 1
        packetArrayLogger.debug("[PacketArrayList] updated firstByteMod15=\(self.firstByteMod15) empty=\(empty)")
        self.opCode = opCode
    }

    func needsMorePacket() -> Bool {
        return firstByteMod15 >= 0
    }

    private mutating func createMessageData() {
        var header = Data([expectedOpCode, expectedTxId, expectedCargoSize])
        messageDataBuffer = header + fullCargo.dropLast(2)
    }

    private mutating func createExpectedCrc() {
        if fullCargo.count >= 2 {
            expectedCrc = fullCargo.suffix(2)
        }
    }

    mutating func buildMessageData() -> Data {
        createMessageData()
        return messageDataBuffer
    }

    mutating func validate(_ authKey: Data) -> Bool {
        if needsMorePacket() { return false }
        createMessageData()
        createExpectedCrc()
        let crc = CalculateCRC16(messageDataBuffer)
        var ok = crc == expectedCrc
        if !ok {
            packetArrayLogger.error("[PacketArrayList] CRC mismatch expected=\(expectedCrc.hexadecimalString) actual=\(crc.hexadecimalString) messageLen=\(messageDataBuffer.count) fullCargoLen=\(fullCargo.count)")
            if shouldIgnoreInvalidHmac(authKey) { ok = true } else { return false }
        }
        if isSigned {
            guard messageDataBuffer.count >= 20 else { return false }
            let msgData = messageDataBuffer.dropLast(20)
            let expectedHmac = messageDataBuffer.suffix(20)
            let mac = HmacSha1(data: msgData, key: authKey)
            if mac != expectedHmac {
                if shouldIgnoreInvalidHmac(authKey) {
                    ok = true
                } else {
                    return false
                }
            }
        }
        return ok
    }

    private func shouldIgnoreInvalidHmac(_ authKey: Data) -> Bool {
        let prefix = Data(PacketArrayList.IGNORE_INVALID_HMAC.utf8)
        if authKey.count < prefix.count { return false }
        return authKey.prefix(prefix.count) == prefix
    }

    struct UnexpectedOpCodeError: Error { let expected: UInt8; let actual: UInt8 }
    struct UnexpectedTransactionIdError: Error { let expected: UInt8; let actual: UInt8 }
    struct InvalidDataSizeError: Error {}
    struct InvalidPacketSequenceError: Error {}
    struct InvalidCargoSizeError: Error { let expected: Int; let actual: Int }
}
