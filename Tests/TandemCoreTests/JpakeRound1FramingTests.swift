import Foundation
@testable import TandemKit
import XCTest

/// A JPAKE round-1 payload is two length-prefixed `(point, ZKP)` groups. The ZKP's scalar is
/// written without its leading zero bytes, so a group is 165 bytes only ~255/256 of the time and
/// the payload is 330 bytes only ~99.2% of the time.
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

    /// The group lengths the peer parses, reading round 1 as both frames concatenated, as pumpX2
    /// does (`Bytes.combine(1a, 1b)`).
    private func peerParsedGroupLengths(_ frames: (first: Data, second: Data)) -> [Int?] {
        let stream = Bytes.combine(frames.first, frames.second)
        let first = JpakeRound1Framing.groupLength(in: stream, at: 0)
        return [first, first.flatMap { JpakeRound1Framing.groupLength(in: stream, at: $0) }]
    }

    func testSplitOfFullLengthPayloadIsCutAtByte165() throws {
        let round1 = makeGroup(scalarLength: 32, seed: 0x10) + makeGroup(scalarLength: 32, seed: 0x40)
        XCTAssertEqual(round1.count, 330)

        let frames = try XCTUnwrap(JpakeRound1Framing.splitRound1(round1))

        XCTAssertEqual(frames.first, round1.subdata(in: 0 ..< 165))
        XCTAssertEqual(frames.second, round1.subdata(in: 165 ..< 330))
    }

    func testAShortFirstGroupRunsOnIntoTheFirstFrameAndThePaddingGoesAtTheEnd() throws {
        let round1 = makeGroup(scalarLength: 31, seed: 0x10) + makeGroup(scalarLength: 32, seed: 0x40)
        XCTAssertEqual(round1.count, 329)

        let frames = try XCTUnwrap(JpakeRound1Framing.splitRound1(round1))

        XCTAssertEqual(frames.first, round1.subdata(in: 0 ..< 165))
        XCTAssertEqual(frames.second, round1.subdata(in: 165 ..< 329) + Data([0]))
        XCTAssertEqual(peerParsedGroupLengths(frames), [164, 165])
    }

    func testAShortSecondGroupIsPaddedAtTheEnd() throws {
        let first = makeGroup(scalarLength: 32, seed: 0x10)
        let second = makeGroup(scalarLength: 31, seed: 0x40)

        let frames = try XCTUnwrap(JpakeRound1Framing.splitRound1(first + second))

        XCTAssertEqual(frames.first, first)
        XCTAssertEqual(frames.second, second + Data([0]))
        XCTAssertEqual(peerParsedGroupLengths(frames), [165, 164])
    }

    func testTwoShortGroupsArePaddedOnlyAtTheEnd() throws {
        let round1 = makeGroup(scalarLength: 30, seed: 0x10) + makeGroup(scalarLength: 29, seed: 0x40)
        XCTAssertEqual(round1.count, 163 + 162)

        let frames = try XCTUnwrap(JpakeRound1Framing.splitRound1(round1))

        XCTAssertEqual(frames.first, round1.subdata(in: 0 ..< 165))
        XCTAssertEqual(frames.second, round1.subdata(in: 165 ..< 325) + Data(repeating: 0, count: 5))
        XCTAssertEqual(peerParsedGroupLengths(frames), [163, 162])
    }

    func testSplitRejectsMalformedPayload() {
        XCTAssertNil(JpakeRound1Framing.splitRound1(Data()))
        XCTAssertNil(JpakeRound1Framing.splitRound1(Data(repeating: 0xFF, count: 330)))
        // One well-formed group and nothing after it.
        XCTAssertNil(JpakeRound1Framing.splitRound1(makeGroup(scalarLength: 32, seed: 0x10)))
    }

    // MARK: - joinRound1

    /// The pump's first frame carries the start of its second group whenever its own first scalar
    /// is short, as pumpX2's server cuts it.
    func testJoinKeepsTheSecondGroupWhenThePumpsFirstScalarIsShort() {
        let round1 = makeGroup(scalarLength: 31, seed: 0x10) + makeGroup(scalarLength: 32, seed: 0x40)

        let joined = JpakeRound1Framing.joinRound1(
            first: round1.subdata(in: 0 ..< 165),
            second: round1.subdata(in: 165 ..< 329) + Data([0])
        )

        XCTAssertEqual(joined.prefix(329), round1)
        XCTAssertEqual(JpakeRound1Framing.groupLength(in: joined, at: 164), 165)
    }

    func testSplitJoinRoundTripsForEveryScalarLengthCombination() throws {
        for firstScalar in 28 ... 32 {
            for secondScalar in 28 ... 32 {
                let first = makeGroup(scalarLength: firstScalar, seed: 0x10)
                let second = makeGroup(scalarLength: secondScalar, seed: 0x40)
                let round1 = first + second
                let frames = try XCTUnwrap(
                    JpakeRound1Framing.splitRound1(round1),
                    "split failed for \(firstScalar)/\(secondScalar)"
                )

                XCTAssertEqual(frames.first.count, 165)
                XCTAssertEqual(frames.second.count, 165)
                XCTAssertEqual(
                    JpakeRound1Framing.joinRound1(first: frames.first, second: frames.second).prefix(round1.count),
                    round1,
                    "\(firstScalar)/\(secondScalar)"
                )
                XCTAssertEqual(peerParsedGroupLengths(frames), [first.count, second.count], "\(firstScalar)/\(secondScalar)")
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
