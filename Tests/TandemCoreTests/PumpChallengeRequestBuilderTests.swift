import XCTest
@testable import TandemCore

final class PumpChallengeRequestBuilderTests: XCTestCase {
    func testValidLongCode() {
        XCTAssertNoThrow(try PumpChallengeRequestBuilder.processPairingCode("abcdefghijklmnop"))
        XCTAssertNoThrow(try PumpChallengeRequestBuilder.processPairingCode("abcd-efgh-ijkl-mnop"))
        XCTAssertNoThrow(try PumpChallengeRequestBuilder.processPairingCode("abcd-1234-ijkl-5678"))
        XCTAssertNoThrow(try PumpChallengeRequestBuilder.processPairingCode("abcd1234ijkl5678"))
        XCTAssertNoThrow(try PumpChallengeRequestBuilder.processPairingCode("abcd-1234-ijkl 5678"))
    }

    func testInvalidLongCode1() {
        XCTAssertThrowsError(try PumpChallengeRequestBuilder.processPairingCode("abcd-!fgh-ijkl-mnop")) { error in
            XCTAssertTrue(error is PumpChallengeRequestBuilder.InvalidLongPairingCodeFormat)
        }
    }

    func testInvalidLongCode2() {
        XCTAssertThrowsError(try PumpChallengeRequestBuilder.processPairingCode("abcd!fghijklmnop")) { error in
            XCTAssertTrue(error is PumpChallengeRequestBuilder.InvalidLongPairingCodeFormat)
        }
    }

    func testInvalidLongCode3() {
        XCTAssertThrowsError(try PumpChallengeRequestBuilder.processPairingCode("abcd--efgh-ijkl-mnop-q")) { error in
            XCTAssertTrue(error is PumpChallengeRequestBuilder.InvalidLongPairingCodeFormat)
        }
    }

    func testInvalidLongCodeIsShortCode() {
        XCTAssertThrowsError(try PumpChallengeRequestBuilder.processPairingCode("123456", type: .long16Char)) { error in
            XCTAssertTrue(error is PumpChallengeRequestBuilder.InvalidLongPairingCodeFormat)
        }
    }

    func testValidShortCode() {
        XCTAssertNoThrow(try PumpChallengeRequestBuilder.processPairingCode("123456"))
        XCTAssertNoThrow(try PumpChallengeRequestBuilder.processPairingCode("123 456"))
        XCTAssertNoThrow(try PumpChallengeRequestBuilder.processPairingCode("123-456"))
        XCTAssertNoThrow(try PumpChallengeRequestBuilder.processPairingCode("123-789"))
    }

    func testInvalidShortCode1() {
        XCTAssertThrowsError(try PumpChallengeRequestBuilder.processPairingCode("123", type: .short6Char)) { error in
            XCTAssertTrue(error is PumpChallengeRequestBuilder.InvalidShortPairingCodeFormat)
        }
    }

    func testInvalidShortCode2() {
        XCTAssertThrowsError(try PumpChallengeRequestBuilder.processPairingCode("1234567", type: .short6Char)) { error in
            XCTAssertTrue(error is PumpChallengeRequestBuilder.InvalidShortPairingCodeFormat)
        }
    }

    func testInvalidShortCode3() {
        XCTAssertThrowsError(try PumpChallengeRequestBuilder.processPairingCode("123 45a", type: .short6Char)) { error in
            XCTAssertTrue(error is PumpChallengeRequestBuilder.InvalidShortPairingCodeFormat)
        }
    }

    func testInvalidShortCodeIsLongCode() {
        XCTAssertThrowsError(try PumpChallengeRequestBuilder.processPairingCode("abcd-efgh-ijkl-mnop", type: .short6Char)) { error in
            XCTAssertTrue(error is PumpChallengeRequestBuilder.InvalidShortPairingCodeFormat)
        }
    }

    func testCreateV1ChallengeReturnsPumpChallengeRequest() throws {
        let pairingCode = "abcd-efgh-ijkl-mnop"
        let response = CentralChallengeResponse(
            appInstanceId: 1,
            centralChallengeHash: Data(repeating: 0xBB, count: 20),
            hmacKey: Data(repeating: 0xAA, count: 8)
        )

        let message = try PumpChallengeRequestBuilder.create(challengeResponse: response, pairingCode: pairingCode)

        guard let challengeRequest = message as? PumpChallengeRequest else {
            XCTFail("Expected PumpChallengeRequest, got \(type(of: message))")
            return
        }

        XCTAssertEqual(challengeRequest.appInstanceId, 1)
        XCTAssertEqual(challengeRequest.pumpChallengeHash.count, 20)
    }

    #if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
    func testCreateV2AdvancesJpakeFlow() throws {
        let pairingCode = "123456"

        // Initialize the JPake builder and send the initial request to mimic real flow
        let builder = JpakeAuthBuilder.initializeWithPairingCode(pairingCode)
        defer { JpakeAuthBuilder.clearInstance() }
        guard let firstMessage = builder.nextRequest() as? Jpake1aRequest else {
            XCTFail("Expected first JPake message to be Jpake1aRequest")
            return
        }
        XCTAssertEqual(firstMessage.centralChallenge.count, 165)

        // Simulate pump response to the first round (165-byte payload)
        let responsePayload = Data(repeating: 0xCD, count: 165)
        let response = Jpake1aResponse(appInstanceId: firstMessage.appInstanceId, centralChallengeHash: responsePayload)

        // Builder will process the response inside createV2 and return the next round request
        let nextMessage = try PumpChallengeRequestBuilder.create(challengeResponse: response, pairingCode: pairingCode)

        guard let round1b = nextMessage as? Jpake1bRequest else {
            XCTFail("Expected next JPake message to be Jpake1bRequest, got \(type(of: nextMessage))")
            return
        }

        XCTAssertEqual(round1b.centralChallenge.count, 165)
    }
    #endif
}
