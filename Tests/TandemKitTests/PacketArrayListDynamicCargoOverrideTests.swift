import Foundation
@testable import TandemBLE
import XCTest

final class PacketArrayListDynamicCargoOverrideTests: XCTestCase {
    func testErrorResponseAllowsTwoByteCargoOverride() throws {
        var packetArrayList = PacketArrayList(
            expectedOpCode: 77,
            expectedCargoSize: 26,
            expectedTxId: 0x55,
            isSigned: false
        )

        XCTAssertNoThrow(try packetArrayList.validatePacket(makePacket(opCode: 77, cargoSize: 2, txId: 0x55)))
        XCTAssertEqual(packetArrayList.buildMessageData()[2], 2)
    }

    func testApiVersionResponseAllowsZeroByteCargoOverride() throws {
        var packetArrayList = PacketArrayList(
            expectedOpCode: 32,
            expectedCargoSize: 2,
            expectedTxId: 0x55,
            isSigned: false
        )

        XCTAssertNoThrow(try packetArrayList.validatePacket(makePacket(opCode: 32, cargoSize: 0, txId: 0x55)))
        XCTAssertEqual(packetArrayList.buildMessageData()[2], 0)
    }

    func testCommonSoftwareInfoRequestAllowsOneByteCargoOverride() throws {
        var packetArrayList = PacketArrayList(
            expectedOpCode: UInt8(bitPattern: Int8(-114)),
            expectedCargoSize: 0,
            expectedTxId: 0x55,
            isSigned: false
        )

        XCTAssertNoThrow(
            try packetArrayList.validatePacket(
                makePacket(opCode: UInt8(bitPattern: Int8(-114)), cargoSize: 1, txId: 0x55)
            )
        )
        XCTAssertEqual(packetArrayList.buildMessageData()[2], 1)
    }

    func testCommonSoftwareInfoResponseAllowsFiftyOneByteCargoOverride() throws {
        var packetArrayList = PacketArrayList(
            expectedOpCode: UInt8(bitPattern: Int8(-113)),
            expectedCargoSize: 60,
            expectedTxId: 0x55,
            isSigned: false
        )

        XCTAssertNoThrow(
            try packetArrayList.validatePacket(
                makePacket(opCode: UInt8(bitPattern: Int8(-113)), cargoSize: 51, txId: 0x55)
            )
        )
        XCTAssertEqual(packetArrayList.buildMessageData()[2], 51)
    }

    func testMalfunctionStatusResponseAllowsTenByteCargoOverride() throws {
        var packetArrayList = PacketArrayList(
            expectedOpCode: 121,
            expectedCargoSize: 11,
            expectedTxId: 0x55,
            isSigned: false
        )

        XCTAssertNoThrow(try packetArrayList.validatePacket(makePacket(opCode: 121, cargoSize: 10, txId: 0x55)))
        XCTAssertEqual(packetArrayList.buildMessageData()[2], 10)
    }

    private func makePacket(opCode: UInt8, cargoSize: Int, txId: UInt8) -> Data {
        let firstByte: UInt8 = 0x50 // lower nibble 0 to indicate no continuation packets
        let header = Data([firstByte, txId, opCode, txId, UInt8(cargoSize)])
        let cargoAndCrc = Data(repeating: 0, count: cargoSize + 2)
        return header + cargoAndCrc
    }
}
