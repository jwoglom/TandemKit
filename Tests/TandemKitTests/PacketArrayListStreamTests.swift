import Foundation
@testable import TandemBLE
import XCTest

final class PacketArrayListStreamTests: XCTestCase {
    func testValidatePacketRejectsOpcodeChangeMidStream() throws {
        var packetArray = PacketArrayList(
            expectedOpCode: 0xAA,
            expectedCargoSize: 0x04,
            expectedTxId: 0x05,
            isSigned: false
        )

        let firstPacket = Data([0x01, 0x05, 0xAA, 0x05, 0x04, 0x10, 0x11, 0x12])
        let secondPacketWrongOpcode = Data([0x00, 0x05, 0xAB, 0x13, 0xC1, 0xC2])

        try packetArray.validatePacket(firstPacket)
        XCTAssertTrue(packetArray.needsMorePacket())

        XCTAssertThrowsError(try packetArray.validatePacket(secondPacketWrongOpcode)) { error in
            guard let opError = error as? PacketArrayList.UnexpectedOpCodeError else {
                XCTFail("Expected UnexpectedOpCodeError, got \(error)")
                return
            }
            XCTAssertEqual(opError.expected, 0xAA)
            XCTAssertEqual(opError.actual, 0xAB)
        }
    }

    func testValidatePacketAcceptsMatchingOpcodeAcrossPackets() throws {
        var packetArray = PacketArrayList(
            expectedOpCode: 0xAA,
            expectedCargoSize: 0x04,
            expectedTxId: 0x05,
            isSigned: false
        )

        let firstPacket = Data([0x01, 0x05, 0xAA, 0x05, 0x04, 0x10, 0x11, 0x12])
        let secondPacket = Data([0x00, 0x05, 0xAA, 0x13, 0xC1, 0xC2])

        try packetArray.validatePacket(firstPacket)
        XCTAssertTrue(packetArray.needsMorePacket())

        try packetArray.validatePacket(secondPacket)
        XCTAssertFalse(packetArray.needsMorePacket())
        XCTAssertEqual(packetArray.opCode, 0xAA)
    }
}
