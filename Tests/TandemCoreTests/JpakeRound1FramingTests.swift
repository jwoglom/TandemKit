import Foundation
@testable import TandemKit
import XCTest

/// A JPAKE round-1 payload is two length-prefixed `(point, ZKP)` groups. The ZKP's scalar is
/// written without its leading zero bytes, so a group is 165 bytes only ~255/256 of the time and
/// the payload is 330 bytes only ~99.2% of the time. These tests pin the framing that keeps the
/// short cases working.
final class JpakeRound1FramingTests: XCTestCase {
    private let pointLength = 65

    /// `[1][65-byte X][1][65-byte V][1][scalar]`, the layout `EcJpake.writeZkp` emits.
    private func makeGroup(scalarLength: Int, seed: UInt8) -> Data {
        var group = Data()
        group.append(UInt8(pointLength))
        group.append(Data(repeating: seed, count: pointLength))
        group.append(UInt8(pointLength))
        group.append(Data(repeating: seed &+ 1, count: pointLength))
        group.append(UInt8(scalarLength))
        group.append(Data(repeating: seed &+ 2, count: scalarLength))
        return group
    }

    // MARK: - groupLength

    func testGroupLengthOfFullWidthGroupIs165() {
        let group = makeGroup(scalarLength: 32, seed: 0x10)
        XCTAssertEqual(group.count, 165)
        XCTAssertEqual(JpakeRound1Framing.groupLength(in: group, at: 0), 165)
    }

    func testGroupLengthFollowsShortScalar() {
        let group = makeGroup(scalarLength: 31, seed: 0x10)
        XCTAssertEqual(group.count, 164)
        XCTAssertEqual(JpakeRound1Framing.groupLength(in: group, at: 0), 164)
    }

    func testGroupLengthOfSecondGroupIsMeasuredFromItsOwnOffset() {
        let first = makeGroup(scalarLength: 31, seed: 0x10)
        let second = makeGroup(scalarLength: 32, seed: 0x40)
        let round1 = first + second

        XCTAssertEqual(JpakeRound1Framing.groupLength(in: round1, at: 0), 164)
        XCTAssertEqual(JpakeRound1Framing.groupLength(in: round1, at: 164), 165)
    }

    func testGroupLengthRejectsTruncatedInput() {
        let group = makeGroup(scalarLength: 32, seed: 0x10)
        XCTAssertNil(JpakeRound1Framing.groupLength(in: group.prefix(100), at: 0))
        XCTAssertNil(JpakeRound1Framing.groupLength(in: Data(), at: 0))
        XCTAssertNil(JpakeRound1Framing.groupLength(in: group, at: 165))
    }

    // MARK: - splitRound1

    /// Regression guard: in the overwhelmingly common case the split must produce exactly what the
    /// old fixed-offset slicing produced, or every existing pairing changes behaviour.
    func testSplitOfFullLengthPayloadMatchesFixedOffsetSlicing() throws {
        let round1 = makeGroup(scalarLength: 32, seed: 0x10) + makeGroup(scalarLength: 32, seed: 0x40)
        XCTAssertEqual(round1.count, 330)

        let frames = try XCTUnwrap(JpakeRound1Framing.splitRound1(round1))

        XCTAssertEqual(frames.first, round1.subdata(in: 0 ..< 165))
        XCTAssertEqual(frames.second, round1.subdata(in: 165 ..< 330))
    }

    /// The case fixed-offset slicing gets wrong: the second frame must start at 164, not 165.
    func testSplitWithShortFirstScalarKeepsSecondGroupAligned() throws {
        let first = makeGroup(scalarLength: 31, seed: 0x10)
        let second = makeGroup(scalarLength: 32, seed: 0x40)
        let round1 = first + second
        XCTAssertEqual(round1.count, 329)

        let frames = try XCTUnwrap(JpakeRound1Framing.splitRound1(round1))

        XCTAssertEqual(frames.first.count, 165)
        XCTAssertEqual(frames.first.prefix(164), first, "First frame should carry the whole first group")
        XCTAssertEqual(frames.first.last, 0, "and be right-padded with a zero byte")
        XCTAssertEqual(frames.second, second, "Second frame must start at the real group boundary")
    }

    /// The case fixed-offset slicing runs off the end of the buffer on.
    func testSplitWithShortSecondScalarPadsSecondFrame() throws {
        let first = makeGroup(scalarLength: 32, seed: 0x10)
        let second = makeGroup(scalarLength: 31, seed: 0x40)
        let round1 = first + second
        XCTAssertEqual(round1.count, 329)

        let frames = try XCTUnwrap(JpakeRound1Framing.splitRound1(round1))

        XCTAssertEqual(frames.first, first)
        XCTAssertEqual(frames.second.count, 165)
        XCTAssertEqual(frames.second.prefix(164), second)
        XCTAssertEqual(frames.second.last, 0)
    }

    func testSplitWithBothScalarsShortPadsBothFrames() throws {
        let first = makeGroup(scalarLength: 30, seed: 0x10)
        let second = makeGroup(scalarLength: 29, seed: 0x40)
        let round1 = first + second
        XCTAssertEqual(round1.count, 163 + 162)

        let frames = try XCTUnwrap(JpakeRound1Framing.splitRound1(round1))

        XCTAssertEqual(frames.first.count, 165)
        XCTAssertEqual(frames.second.count, 165)
        XCTAssertEqual(frames.first.prefix(163), first)
        XCTAssertEqual(frames.second.prefix(162), second)
        XCTAssertEqual(Array(frames.first.suffix(2)), [0, 0])
        XCTAssertEqual(Array(frames.second.suffix(3)), [0, 0, 0])
    }

    func testSplitRejectsMalformedPayload() {
        XCTAssertNil(JpakeRound1Framing.splitRound1(Data()))
        XCTAssertNil(JpakeRound1Framing.splitRound1(Data(repeating: 0xFF, count: 330)))
        // One well-formed group and nothing after it.
        XCTAssertNil(JpakeRound1Framing.splitRound1(makeGroup(scalarLength: 32, seed: 0x10)))
    }

    // MARK: - joinRound1

    func testJoinStripsPaddingFromTheFirstFrame() throws {
        let first = makeGroup(scalarLength: 31, seed: 0x10)
        let second = makeGroup(scalarLength: 32, seed: 0x40)
        let round1 = first + second
        let frames = try XCTUnwrap(JpakeRound1Framing.splitRound1(round1))

        let rejoined = JpakeRound1Framing.joinRound1(first: frames.first, second: frames.second)

        XCTAssertEqual(rejoined, round1)
    }

    /// Trailing padding on the *second* frame is harmless — the parser stops before it — so join
    /// leaves it in place rather than guessing at the payload's true end.
    func testJoinParsesAsTwoGroupsWhenSecondFrameIsPadded() throws {
        let first = makeGroup(scalarLength: 32, seed: 0x10)
        let second = makeGroup(scalarLength: 31, seed: 0x40)
        let frames = try XCTUnwrap(JpakeRound1Framing.splitRound1(first + second))

        let rejoined = JpakeRound1Framing.joinRound1(first: frames.first, second: frames.second)

        let firstLength = try XCTUnwrap(JpakeRound1Framing.groupLength(in: rejoined, at: 0))
        XCTAssertEqual(firstLength, 165)
        XCTAssertEqual(JpakeRound1Framing.groupLength(in: rejoined, at: firstLength), 164)
    }

    func testSplitJoinRoundTripsForEveryScalarLengthCombination() throws {
        for firstScalar in 28 ... 32 {
            for secondScalar in 28 ... 32 {
                let first = makeGroup(scalarLength: firstScalar, seed: 0x10)
                let second = makeGroup(scalarLength: secondScalar, seed: 0x40)
                let frames = try XCTUnwrap(
                    JpakeRound1Framing.splitRound1(first + second),
                    "split failed for \(firstScalar)/\(secondScalar)"
                )

                XCTAssertEqual(frames.first.count, 165)
                XCTAssertEqual(frames.second.count, 165)

                let rejoined = JpakeRound1Framing.joinRound1(first: frames.first, second: frames.second)
                let firstLength = try XCTUnwrap(JpakeRound1Framing.groupLength(in: rejoined, at: 0))
                XCTAssertEqual(firstLength, first.count)
                XCTAssertEqual(
                    JpakeRound1Framing.groupLength(in: rejoined, at: firstLength),
                    second.count,
                    "second group misaligned for \(firstScalar)/\(secondScalar)"
                )
            }
        }
    }
}

#if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)

    /// The framing has to be transparent to the crypto: a payload that goes out as two frames and
    /// comes back reassembled must still let both sides agree on a secret.
    final class JpakeRound1FramingCryptoTests: XCTestCase {
        func testHandshakeSurvivesFrameSplitAndRejoin() throws {
            let password = Data("123456".utf8)
            let client = EcJpake(role: .client, password: password, random: JpakeAuthBuilder.defaultRandom)
            let server = EcJpake(role: .server, password: password, random: JpakeAuthBuilder.defaultRandom)

            // Each side's round 1 goes out as two 165-byte frames and is reassembled by the peer,
            // exactly as JpakeAuthBuilder does over the wire.
            let clientFrames = try XCTUnwrap(JpakeRound1Framing.splitRound1(client.getRound1()))
            let serverFrames = try XCTUnwrap(JpakeRound1Framing.splitRound1(server.getRound1()))
            XCTAssertEqual(clientFrames.first.count, 165)
            XCTAssertEqual(clientFrames.second.count, 165)

            client.readRound1(JpakeRound1Framing.joinRound1(first: serverFrames.first, second: serverFrames.second))
            server.readRound1(JpakeRound1Framing.joinRound1(first: clientFrames.first, second: clientFrames.second))

            let clientRound2 = client.getRound2()
            let serverRound2 = server.getRound2()
            client.readRound2(serverRound2)
            server.readRound2(clientRound2)

            let clientSecret = client.deriveSecret()
            XCTAssertFalse(clientSecret.isEmpty)
            XCTAssertEqual(clientSecret, server.deriveSecret())
        }

        /// A real round-1 payload must always split into two frames, whatever length the scalars
        /// happened to encode to.
        func testRealRound1AlwaysSplitsIntoTwoFrames() throws {
            for index in 0 ..< 5 {
                let jpake = EcJpake(
                    role: .client,
                    password: Data("12345\(index)".utf8),
                    random: JpakeAuthBuilder.defaultRandom
                )
                let round1 = jpake.getRound1()
                let frames = try XCTUnwrap(
                    JpakeRound1Framing.splitRound1(round1),
                    "round 1 of \(round1.count) bytes failed to split"
                )
                XCTAssertEqual(frames.first.count, 165)
                XCTAssertEqual(frames.second.count, 165)
            }
        }
    }

#endif
