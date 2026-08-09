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

        func testEcJpakeRound1HasExpectedSize() {
            let start = Date()

            let jpake = EcJpake(
                role: .client,
                password: Data("123456".utf8),
                random: JpakeAuthBuilder.defaultRandom
            )
            let round1 = jpake.getRound1()

            logElapsed("first getRound1()", since: start)
            XCTAssertEqual(round1.count, 330, "getRound1 should return 330 bytes (2 key pairs)")
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
        func testRepeatedRound1CallsStaySized() {
            for index in 0 ..< 3 {
                let start = Date()
                let jpake = EcJpake(
                    role: .client,
                    password: Data("12345\(index)".utf8),
                    random: JpakeAuthBuilder.defaultRandom
                )
                XCTAssertEqual(jpake.getRound1().count, 330)
                logElapsed("getRound1() call \(index + 1)", since: start)
            }
        }
    }

#endif
