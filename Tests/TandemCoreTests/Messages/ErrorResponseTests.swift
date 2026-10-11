@testable import TandemKit
import XCTest

final class ErrorResponseTests: XCTestCase {
    func testErrorResponseBadOpcode() {
        let expected = ErrorResponse(requestCodeId: -112, errorCode: .badOpcode)

        let parsed: ErrorResponse = MessageTester.test(
            "00054d05029006168b",
            5,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(144, parsed.requestCodeId)
        XCTAssertEqual(144, expected.requestCodeId)
        XCTAssertEqual(.badOpcode, parsed.errorCode)
    }

    func testErrorResponseInvalidParameter() {
        let expected = ErrorResponse(requestCodeId: 66, errorCode: .invalidRequiredParameter)

        let parsed: ErrorResponse = MessageTester.test(
            "00084d08024207f4d1",
            8,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(66, parsed.requestCodeId)
        XCTAssertEqual(.invalidRequiredParameter, parsed.errorCode)
    }
}
