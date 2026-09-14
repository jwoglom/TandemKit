import CoreBluetooth
import Foundation
@testable import TandemKit
import XCTest

/// A JPAKE ZKP scalar is written with its leading zero bytes stripped, so the pump's round-1 and
/// round-2 payloads are one byte short about 1 time in 256 and shorter still beyond that. These
/// tests drive genuinely short payloads through the real notification assembly path — the one that
/// ends in `Message.init(cargo:)`, where an over-long `subdata` range traps instead of throwing.
final class JpakeShortScalarReceiveTests: XCTestCase {
    private static let pointLength = 65
    /// The parser leaves the packet CRC on the assembled cargo; its value is never checked.
    private static let crc = Data([0x9b, 0xe8])

    /// `[1][65-byte X][1][65-byte V][1][scalar]`, the layout `EcJpake.writeZkp` emits.
    private func group(scalarLength: Int, seed: UInt8 = 0x10) -> Data {
        var group = Data()
        group.append(UInt8(Self.pointLength))
        group.append(Data(repeating: seed, count: Self.pointLength))
        group.append(UInt8(Self.pointLength))
        group.append(Data(repeating: seed &+ 1, count: Self.pointLength))
        group.append(UInt8(scalarLength))
        group.append(Data(repeating: seed &+ 2, count: scalarLength))
        return group
    }

    /// Round 2 as the pump sends it: a curve id followed by one group.
    private func round2Payload(scalarLength: Int) -> Data {
        Data([0x03, 0x00, 0x17]) + group(scalarLength: scalarLength)
    }

    /// The BLE notifications a pump sends for one message, framed exactly as `Packetize` frames a
    /// request: `[packetsRemaining][txId]` over `[opCode][txId][length]` + cargo + CRC.
    private func notifications(opCode: UInt8, cargo: Data, txId: UInt8 = 0x02, chunkSize: Int = 18) -> [Data] {
        let body = Data([opCode, txId, UInt8(cargo.count)]) + cargo + Self.crc
        var chunks: [Data] = []
        var index = body.startIndex
        while index < body.endIndex {
            let end = Swift.min(index + chunkSize, body.endIndex)
            chunks.append(body.subdata(in: index ..< end))
            index = end
        }
        // BTResponseParser drops notifications of 4 bytes or fewer, so never leave a 1-byte tail.
        if chunks.count > 1, chunks[chunks.count - 1].count < 3 {
            let tail = chunks.removeLast()
            let previous = chunks.removeLast()
            let split = previous.startIndex + previous.count - 3
            chunks.append(previous.subdata(in: previous.startIndex ..< split))
            chunks.append(previous.subdata(in: split ..< previous.endIndex) + tail)
        }
        return chunks.enumerated().map { offset, chunk in
            Data([UInt8(chunks.count - 1 - offset), txId]) + chunk
        }
    }

    private func parse(_ packets: [Data]) -> Message? {
        var response = ResponseMessage()
        for packet in packets {
            BTResponseParser.parse(
                data: packet,
                characteristic: CharacteristicUUID.AUTHORIZATION_CHARACTERISTICS,
                authKey: nil,
                response: &response
            )
        }
        return response.message
    }

    private func receiveJpake2(payload: Data) -> Jpake2Response? {
        parse(notifications(opCode: Jpake2Response.props.opCode, cargo: Data([0x00, 0x00]) + payload)) as? Jpake2Response
    }

    private func receiveJpake1a(payload: Data) -> Jpake1aResponse? {
        parse(notifications(opCode: Jpake1aResponse.props.opCode, cargo: Data([0x00, 0x00]) + payload)) as? Jpake1aResponse
    }

    private func receiveJpake1b(payload: Data) -> Jpake1bResponse? {
        parse(notifications(opCode: Jpake1bResponse.props.opCode, cargo: Data([0x00, 0x00]) + payload)) as? Jpake1bResponse
    }

    // MARK: - Round 2

    func testFullLengthRound2IsUnaffected() throws {
        let payload = round2Payload(scalarLength: 32)
        XCTAssertEqual(payload.count, 168)

        let response = try XCTUnwrap(receiveJpake2(payload: payload))

        XCTAssertEqual(response.appInstanceId, 0)
        XCTAssertEqual(response.centralChallengeHash, payload)
    }

    func testRound2WithAShortScalarKeepsTheWholeGroupIntact() throws {
        for scalarLength in 20 ... 31 {
            let payload = round2Payload(scalarLength: scalarLength)
            let response = try XCTUnwrap(receiveJpake2(payload: payload), "dropped for scalar \(scalarLength)")

            XCTAssertEqual(
                response.centralChallengeHash.prefix(payload.count),
                payload,
                "payload corrupted for scalar \(scalarLength)"
            )
            XCTAssertEqual(
                JpakeRound1Framing.groupLength(in: response.centralChallengeHash.dropFirst(3), at: 0),
                133 + scalarLength,
                "group misaligned for scalar \(scalarLength)"
            )
        }
    }

    /// Regression: a payload three or more bytes short makes the cargo shorter than the declared
    /// 170 bytes even after the CRC, which is where `cargo.subdata(in: 2 ..< 170)` used to trap.
    func testRound2ShorterThanTheDeclaredSizeParsesRatherThanTrapping() throws {
        let payload = round2Payload(scalarLength: 29)
        XCTAssertEqual(Data([0x00, 0x00]).count + payload.count + Self.crc.count, 169)

        let response = try XCTUnwrap(receiveJpake2(payload: payload))

        XCTAssertEqual(response.centralChallengeHash.prefix(payload.count), payload)
    }

    func testCargoTooShortToBeAnyRound2PayloadIsDropped() {
        XCTAssertNil(receiveJpake2(payload: round2Payload(scalarLength: 32).prefix(60)))
    }

    func testTruncatedNotificationIsDroppedRatherThanTrapping() {
        let packet = Data([0x00, 0x02, Jpake2Response.props.opCode, 0x02, 0xAA, 0x01, 0x02])
        XCTAssertNil(parse([packet]))
    }

    // MARK: - Round 1

    /// The pump's two round-1 frames must rejoin into exactly the payload it generated, whether it
    /// pads a short group out to the frame size or sends the group short.
    func testRound1FramesWithAShortFirstGroupRejoinExactly() throws {
        for firstScalar in 29 ... 32 {
            for padded in [true, false] {
                let first = group(scalarLength: firstScalar, seed: 0x10)
                let second = group(scalarLength: 32, seed: 0x40)
                let firstFrame = padded ? JpakeRound1Framing.padToFrame(first) : first

                let a = try XCTUnwrap(receiveJpake1a(payload: firstFrame), "1a dropped for \(firstScalar)/\(padded)")
                let b = try XCTUnwrap(receiveJpake1b(payload: second), "1b dropped for \(firstScalar)/\(padded)")

                let rejoined = JpakeRound1Framing.joinRound1(
                    first: a.centralChallengeHash,
                    second: b.centralChallengeHash
                )
                XCTAssertEqual(rejoined.prefix(first.count + second.count), first + second)
                XCTAssertEqual(JpakeRound1Framing.groupLength(in: rejoined, at: 0), first.count)
                XCTAssertEqual(JpakeRound1Framing.groupLength(in: rejoined, at: first.count), second.count)
            }
        }
    }

    func testRound1FrameWithAShortSecondGroupLeavesThePayloadParseable() throws {
        let first = group(scalarLength: 32, seed: 0x10)
        let second = group(scalarLength: 29, seed: 0x40)

        let a = try XCTUnwrap(receiveJpake1a(payload: first))
        let b = try XCTUnwrap(receiveJpake1b(payload: second))

        let rejoined = JpakeRound1Framing.joinRound1(first: a.centralChallengeHash, second: b.centralChallengeHash)
        XCTAssertEqual(rejoined.prefix(first.count + second.count), first + second)
        XCTAssertEqual(JpakeRound1Framing.groupLength(in: rejoined, at: first.count), second.count)
    }

    // MARK: - Genuinely fixed-size messages

    func testFixedSizeJpakeResponsesStillRequireTheirFullCargo() throws {
        let nonce = Data(repeating: 0x11, count: 8)
        let reserved = Data(repeating: 0x00, count: 8)
        let digest = Data(repeating: 0x22, count: 32)

        let three = Jpake3SessionKeyResponse(appInstanceId: 0, nonce: nonce, reserved: reserved)
        let parsedThree = try XCTUnwrap(
            parse(notifications(opCode: Jpake3SessionKeyResponse.props.opCode, cargo: three.cargo))
                as? Jpake3SessionKeyResponse
        )
        XCTAssertEqual(parsedThree.deviceKeyNonce, nonce)
        XCTAssertNil(parse(notifications(opCode: Jpake3SessionKeyResponse.props.opCode, cargo: three.cargo.prefix(10))))

        let four = Jpake4KeyConfirmationResponse(appInstanceId: 0, nonce: nonce, reserved: reserved, hashDigest: digest)
        let parsedFour = try XCTUnwrap(
            parse(notifications(opCode: Jpake4KeyConfirmationResponse.props.opCode, cargo: four.cargo))
                as? Jpake4KeyConfirmationResponse
        )
        XCTAssertEqual(parsedFour.hashDigest, digest)
        XCTAssertNil(
            parse(notifications(opCode: Jpake4KeyConfirmationResponse.props.opCode, cargo: four.cargo.prefix(30)))
        )
    }

    // MARK: - Real handshake

    /// The assembled cargo keeps the packet CRC, so the payload every JPAKE response hands back is
    /// two bytes longer than what the pump generated. That has to be transparent to the crypto.
    func testRealHandshakeSurvivesTheReceivePath() throws {
        #if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
            let password = Data("123456".utf8)
            let client = EcJpake(role: .client, password: password, random: JpakeAuthBuilder.defaultRandom)
            let pump = EcJpake(role: .server, password: password, random: JpakeAuthBuilder.defaultRandom)

            let pumpFrames = try XCTUnwrap(JpakeRound1Framing.splitRound1(pump.getRound1()))
            let a = try XCTUnwrap(receiveJpake1a(payload: pumpFrames.first))
            let b = try XCTUnwrap(receiveJpake1b(payload: pumpFrames.second))
            client.readRound1(JpakeRound1Framing.joinRound1(first: a.centralChallengeHash, second: b.centralChallengeHash))

            let clientFrames = try XCTUnwrap(JpakeRound1Framing.splitRound1(client.getRound1()))
            pump.readRound1(JpakeRound1Framing.joinRound1(first: clientFrames.first, second: clientFrames.second))

            let two = try XCTUnwrap(receiveJpake2(payload: pump.getRound2()))
            client.readRound2(two.centralChallengeHash)
            pump.readRound2(client.getRound2())

            let secret = client.deriveSecret()
            XCTAssertFalse(secret.isEmpty)
            XCTAssertEqual(secret, pump.deriveSecret())
        #endif
    }

    // MARK: - Direct construction

    func testConstructingAChallengeResponseFromShortCargoDoesNotTrap() {
        XCTAssertEqual(Jpake2Response(cargo: Data(repeating: 0x01, count: 100)).centralChallengeHash.count, 98)
        XCTAssertEqual(Jpake1aResponse(cargo: Data(repeating: 0x01, count: 50)).centralChallengeHash.count, 48)
        XCTAssertEqual(Jpake1bResponse(cargo: Data(repeating: 0x01, count: 3)).centralChallengeHash.count, 1)
        XCTAssertTrue(Jpake2Response(cargo: Data()).centralChallengeHash.isEmpty)
        XCTAssertTrue(Jpake2Response(cargo: Data([0x00, 0x00])).centralChallengeHash.isEmpty)
    }
}
