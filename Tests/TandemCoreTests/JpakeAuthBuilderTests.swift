import Foundation
@testable import TandemCore
import XCTest

#if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)

    final class JpakeAuthBuilderTests: XCTestCase {
        func testPairingCodeConversion() throws {
            let bytes = JpakeAuthBuilder.pairingCodeToBytes("123456")
            XCTAssertEqual(bytes, Data([49, 50, 51, 52, 53, 54]))
        }

        func testInitialStep() throws {
            XCTAssertEqual(JpakeAuthBuilder.decideInitialStep(derivedSecret: nil), .BOOTSTRAP_INITIAL)
            XCTAssertEqual(JpakeAuthBuilder.decideInitialStep(derivedSecret: Data([1])), .CONFIRM_INITIAL)
        }

        func testNextRequestBootstrap() throws {
            let builder = JpakeAuthBuilder(pairingCode: "123456", derivedSecret: nil, rand: AllZeroSecureRandom.nextBytes)
            let req = builder.nextRequest()
            XCTAssertTrue(req is Jpake1aRequest)
            let chal = (req as! Jpake1aRequest).centralChallenge
            XCTAssertEqual(chal.count, 165)
            XCTAssertEqual(builder.step, .ROUND_1A_SENT)
        }
    }

#endif
