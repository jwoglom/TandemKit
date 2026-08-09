import Foundation
@testable import TandemKit
import XCTest

#if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
    import BigInt
    import SwiftECC

    /// Smoke tests for the elliptic-curve work behind JPAKE pairing.
    ///
    /// SwiftECC's first curve operation is slow (it warms up `Domain.instance`), which is why the
    /// driver primes the builder off the main thread during pairing. Timings are logged here for
    /// diagnosis but deliberately not asserted on: shared CI runners make wall-clock budgets a
    /// source of false failures, not signal. The assertions cover shape and correctness only.
    final class EcJpakePerformanceTests: XCTestCase {
        private func logElapsed(_ label: String, since start: Date) {
            print("[EcJpakePerformance] \(label): \(String(format: "%.3f", Date().timeIntervalSince(start)))s")
        }

        func testDefaultRandomProducesRequestedLength() {
            let start = Date()

            for _ in 0 ..< 100 {
                XCTAssertEqual(JpakeAuthBuilder.defaultRandom(32).count, 32)
            }

            logElapsed("100x defaultRandom(32)", since: start)
        }

        func testDefaultRandomIsNotConstant() {
            let first = JpakeAuthBuilder.defaultRandom(32)
            let second = JpakeAuthBuilder.defaultRandom(32)

            XCTAssertNotEqual(first, second, "Pairing security depends on these bytes being unpredictable")
        }

        /// Round 1 is two (point, ZKP) pairs. Each ZKP ends in a length-prefixed scalar written by
        /// `writeNum`, which uses `asMagnitudeBytes()` and therefore drops leading zero bytes — so
        /// a scalar is 32 bytes only about 255/256 of the time and the total is 330 bytes only
        /// about 99.2% of the time.
        ///
        /// This is not merely a test detail: `JpakeAuthBuilder.nextRequest()` slices `clientRound1`
        /// at fixed offsets 0..<165 and 165..<330, which is wrong whenever a scalar comes up short.
        /// See the pairing notes in AGENTS.md.
        func testEcJpakeRound1SizeIsWithinEncodingRange() {
            let start = Date()

            let jpake = EcJpake(
                role: .client,
                password: Data("123456".utf8),
                random: JpakeAuthBuilder.defaultRandom
            )
            let round1 = jpake.getRound1()

            logElapsed("first getRound1()", since: start)
            XCTAssertTrue(
                (320 ... 330).contains(round1.count),
                "getRound1 should be at most 330 bytes (2 key pairs), got \(round1.count)"
            )
        }

        /// Client and server must agree on a secret regardless of how the scalars happened to
        /// encode. This is the invariant that actually matters, and it holds for every length.
        func testEcJpakeRoundTripDerivesMatchingSecret() {
            let password = Data("123456".utf8)
            let client = EcJpake(role: .client, password: password, random: JpakeAuthBuilder.defaultRandom)
            let server = EcJpake(role: .server, password: password, random: JpakeAuthBuilder.defaultRandom)

            let clientRound1 = client.getRound1()
            let serverRound1 = server.getRound1()
            client.readRound1(serverRound1)
            server.readRound1(clientRound1)

            let clientRound2 = client.getRound2()
            let serverRound2 = server.getRound2()
            client.readRound2(serverRound2)
            server.readRound2(clientRound2)

            let clientSecret = client.deriveSecret()
            XCTAssertFalse(clientSecret.isEmpty)
            XCTAssertEqual(clientSecret, server.deriveSecret())
        }

        func testSwiftECCDomainInitializationAndPointMultiplication() throws {
            let domainStart = Date()
            let domain = Domain.instance(curve: .EC256r1)
            logElapsed("Domain.instance(.EC256r1)", since: domainStart)

            let multiplyStart = Date()
            let point = try domain.multiplyPoint(domain.g, BInt(magnitude: [42]))
            logElapsed("first multiplyPoint", since: multiplyStart)

            XCTAssertTrue(domain.contains(point), "Scalar multiple of the generator must stay on the curve")
        }

        func testJpakeAuthBuilderFirstRequestIsRound1a() throws {
            JpakeAuthBuilder.clearInstance()
            defer { JpakeAuthBuilder.clearInstance() }

            let start = Date()
            let builder = JpakeAuthBuilder.initializeWithPairingCode("123456")
            let next = builder.nextRequest()
            logElapsed("initialize + nextRequest", since: start)

            let request = try XCTUnwrap(next?.0, "The builder should produce a first request")
            XCTAssertTrue(request is Jpake1aRequest, "First request should be Jpake1aRequest")
        }

        /// Repeated round-1 generation should keep working after the first (warm-up) call — this is
        /// the path a retry during pairing takes.
        func testRepeatedRound1CallsStayWithinEncodingRange() {
            for index in 0 ..< 3 {
                let start = Date()
                let jpake = EcJpake(
                    role: .client,
                    password: Data("12345\(index)".utf8),
                    random: JpakeAuthBuilder.defaultRandom
                )
                let count = jpake.getRound1().count
                XCTAssertTrue((320 ... 330).contains(count), "Round 1 was \(count) bytes")
                logElapsed("getRound1() call \(index + 1)", since: start)
            }
        }
    }

#endif
