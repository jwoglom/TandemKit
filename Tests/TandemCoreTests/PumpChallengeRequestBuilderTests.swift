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
}
