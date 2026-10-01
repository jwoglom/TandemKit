@testable import TandemKit
import XCTest

final class ApiVersionResponseTests: XCTestCase {
    func testApiVersionResponseSW71() {
        let expected = ApiVersionResponse(majorVersion: 2, minorVersion: 0)

        let parsed: ApiVersionResponse = MessageTester.test(
            "00022102040200000077c8",
            2,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(2, parsed.majorVersion)
        XCTAssertEqual(0, parsed.minorVersion)
    }

    func testApiVersionResponseSW74() {
        let expected = ApiVersionResponse(majorVersion: 2, minorVersion: 1)

        let parsed: ApiVersionResponse = MessageTester.test(
            "00072107040200010047b8",
            7,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(2, parsed.majorVersion)
        XCTAssertEqual(1, parsed.minorVersion)
    }

    func testApiVersionResponseMobi() {
        let expected = ApiVersionResponse(majorVersion: 3, minorVersion: 5)

        let parsed: ApiVersionResponse = MessageTester.test(
            "000421040403000500d7cc",
            4,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(3, parsed.majorVersion)
        XCTAssertEqual(5, parsed.minorVersion)
    }
}
