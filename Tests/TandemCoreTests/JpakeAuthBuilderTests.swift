import Foundation
@testable import TandemKit
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
            let builder = JpakeAuthBuilder.initializeWithPairingCode("123456")
            let next = try XCTUnwrap(builder.nextRequest())
            let request = try XCTUnwrap(next as? Jpake1aRequest)
            XCTAssertEqual(request.centralChallenge.count, 165)
            XCTAssertTrue(type(of: next).responseType is Jpake1aResponse.Type)
            XCTAssertEqual(builder.step, .ROUND_1A_SENT)
        }
    }

#endif
