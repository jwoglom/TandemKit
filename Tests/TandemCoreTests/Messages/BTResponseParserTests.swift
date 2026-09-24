import CoreBluetooth
@testable import TandemKit
import XCTest

final class BTResponseParserTests: XCTestCase {
    private let nonce = Data([0xE6, 0x8B, 0x38, 0xDA, 0x41, 0x3F, 0xC8, 0x68])
    private let digest = Data((0 ..< 32).map { UInt8($0) })

    private func parse(_ packets: [Packet], characteristic: CBUUID) -> ResponseMessage {
        var response = ResponseMessage()
        for packet in packets {
            BTResponseParser.parse(data: packet.build(), characteristic: characteristic, authKey: nil, response: &response)
        }
        return response
    }

    /// 3 header + 50 cargo + 2 CRC = 55 bytes chunked by 18 leaves a one-byte tail, i.e. a
    /// three-byte final notification. It used to be rejected as too short, so the message never
    /// completed and the write timed out.
    func testAThreeBytePacketCompletesTheMessage() {
        let message = Jpake4KeyConfirmationResponse(appInstanceId: 0, nonce: nonce, reserved: Data(count: 8), hashDigest: digest)
        let packets = Packetize.parse(message: message, authenticationKey: nil, txId: 1, timeSinceReset: nil)
        XCTAssertEqual(packets.map { $0.build().count }, [20, 20, 20, 3])

        let response = parse(packets, characteristic: Jpake4KeyConfirmationResponse.props.characteristic)

        XCTAssertFalse(response.needsMorePacket)
        XCTAssertEqual(response.opCode, Jpake4KeyConfirmationResponse.props.opCode)
        XCTAssertEqual((response.message as? Jpake4KeyConfirmationResponse)?.hashDigest, digest)
    }

    func testAnIncompleteMessageKeepsAskingForMore() {
        let message = Jpake4KeyConfirmationResponse(appInstanceId: 0, nonce: nonce, reserved: Data(count: 8), hashDigest: digest)
        let packets = Packetize.parse(message: message, authenticationKey: nil, txId: 1, timeSinceReset: nil)

        let response = parse(Array(packets.dropLast()), characteristic: Jpake4KeyConfirmationResponse.props.characteristic)

        XCTAssertTrue(response.needsMorePacket)
        XCTAssertNil(response.message)
    }

    func testATwoBytePacketIsStillRejected() {
        var response = ResponseMessage()
        BTResponseParser.parse(
            data: Data([0x01, 0x27, 0x00, 0x00]),
            characteristic: Jpake3SessionKeyResponse.props.characteristic,
            authKey: nil,
            response: &response
        )
        XCTAssertTrue(response.needsMorePacket)
        BTResponseParser.parse(data: Data([0x00, 0x27]), characteristic: Jpake3SessionKeyResponse.props.characteristic, authKey: nil, response: &response)
        XCTAssertTrue(response.needsMorePacket, "a packet without payload is dropped, not treated as the end")
    }
}
