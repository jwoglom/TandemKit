@testable import TandemKit
import XCTest

final class PacketAssemblerTests: XCTestCase {
    private let nonce = Data([0xE6, 0x8B, 0x38, 0xDA, 0x41, 0x3F, 0xC8, 0x68])
    private let digest = Data((0 ..< 32).map { UInt8($0) })

    private var keyConfirmation: Jpake4KeyConfirmationResponse {
        Jpake4KeyConfirmationResponse(appInstanceId: 0, nonce: nonce, reserved: Data(count: 8), hashDigest: digest)
    }

    private func packets(_ message: Message, txId: UInt8 = 1) -> [Data] {
        Packetize.parse(message: message, authenticationKey: nil, txId: txId, timeSinceReset: nil).map { $0.build() }
    }

    private func take(_ packets: [Data], into assembler: inout PacketAssembler) -> [PacketAssembler.Step] {
        packets.map { assembler.take($0) }
    }

    private func assembled(_ step: PacketAssembler.Step?) -> AssembledMessage? {
        if case let .complete(message) = step {
            return message
        }
        return nil
    }

    /// 3 header + 50 cargo + 2 CRC = 55 bytes chunked by 18 leaves a three-byte last notification.
    func testAThreeBytePacketCompletesTheMessage() throws {
        let packets = packets(keyConfirmation)
        XCTAssertEqual(packets.map(\.count), [20, 20, 20, 3])
        var assembler = PacketAssembler()

        let steps = take(packets, into: &assembler)

        XCTAssertEqual(steps.dropLast(), [.needsMore, .needsMore, .needsMore])
        let message = try XCTUnwrap(assembled(steps.last))
        XCTAssertEqual(message.opCode, Jpake4KeyConfirmationResponse.props.opCode)
        XCTAssertEqual(message.txId, 1)
        let decoded = BTResponseParser.decode(message, characteristic: Jpake4KeyConfirmationResponse.props.characteristic)
        XCTAssertEqual((decoded as? Jpake4KeyConfirmationResponse)?.hashDigest, digest)
        XCTAssertTrue(assembler.isEmpty)
    }

    func testAnIncompleteMessageKeepsAskingForMore() {
        var assembler = PacketAssembler()

        let steps = take(Array(packets(keyConfirmation).dropLast()), into: &assembler)

        XCTAssertEqual(steps, [.needsMore, .needsMore, .needsMore])
        XCTAssertFalse(assembler.isEmpty)
    }

    func testAPacketWithoutPayloadIsNotTaken() {
        var assembler = PacketAssembler()
        XCTAssertEqual(assembler.take(Data([0x01, 0x27, 0x00, 0x27, 0x10])), .needsMore)

        XCTAssertEqual(assembler.take(Data([0x00, 0x27])), .notPart)
        XCTAssertFalse(assembler.isEmpty)
    }

    func testAFirstPieceCarriesItsTxIdTwice() {
        var assembler = PacketAssembler()
        var first = packets(keyConfirmation)[0]
        first[3] &+= 1

        XCTAssertNil(PacketAssembler.start(of: first))
        XCTAssertEqual(assembler.take(first), .notPart)
        XCTAssertTrue(assembler.isEmpty)
    }

    func testAPieceUnderAnotherTxIdIsNotPartOfTheMessage() throws {
        let ours = packets(keyConfirmation, txId: 1)
        let theirs = packets(keyConfirmation, txId: 2)
        var assembler = PacketAssembler()

        XCTAssertEqual(assembler.take(ours[0]), .needsMore)
        XCTAssertEqual(assembler.take(theirs[0]), .notPart)
        XCTAssertEqual(assembler.take(theirs[1]), .notPart)
        let steps = take(Array(ours.dropFirst()), into: &assembler)

        XCTAssertEqual(try XCTUnwrap(assembled(steps.last)).txId, 1)
    }

    func testAPieceOutOfSequenceIsNotPartOfTheMessage() {
        let packets = packets(keyConfirmation)
        var assembler = PacketAssembler()

        XCTAssertEqual(assembler.take(packets[0]), .needsMore)
        XCTAssertEqual(assembler.take(packets[2]), .notPart)
        XCTAssertEqual(assembler.take(packets[1]), .needsMore)
    }

    func testAMessageWhoseCRCDoesNotMatchIsCorrupt() {
        var packet = packets(ApiVersionResponse(majorVersion: 3, minorVersion: 7))[0]
        packet[5] ^= 0x01
        var assembler = PacketAssembler()

        XCTAssertEqual(assembler.take(packet), .corrupt("CRC does not match"))
        XCTAssertTrue(assembler.isEmpty)
    }

    func testAMessageLongerThanItsHeaderDeclaresIsCorrupt() {
        let body = Data([ApiVersionResponse.props.opCode, 0x05, 4, 3, 0, 7, 0, 0xFF])
        var assembler = PacketAssembler()

        let step = assembler.take(Data([0, 0x05]) + body + CalculateCRC16(body))

        XCTAssertEqual(step, .corrupt("10 bytes where its header declares 9"))
    }

    /// pumpX2's captures: a status response, a signed control-stream message and a history log
    /// stream message, each whole in one notification.
    func testCapturedPumpMessagesPassTheirChecks() throws {
        let captures: [(hex: String, opCode: UInt8, payloadLength: Int)] = [
            ("0003290309200300000000000001d8d0", CurrentBasalStatusResponse.props.opCode, 9),
            ("0089e3891a140078c84020f4eabab90ec17db0da1b4d99095f92c063a1b1b9456a", DetectingCartridgeStateStreamResponse.props.opCode, 26),
            ("000081001c01045a00800d941a00000000000000009add200200000000000000004834", HistoryLogStreamResponse.props.opCode, 28),
        ]

        for capture in captures {
            var assembler = PacketAssembler()
            let message = try XCTUnwrap(assembled(assembler.take(try XCTUnwrap(Data(hexadecimalString: capture.hex)))), capture.hex)
            XCTAssertEqual(message.opCode, capture.opCode)
            XCTAssertEqual(message.payloadLength, capture.payloadLength)
            XCTAssertEqual(message.cargo.count, capture.payloadLength + 2, "the cargo keeps the CRC")
        }
    }
}
