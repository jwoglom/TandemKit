import XCTest
@testable import TandemCore

final class BasalLimitSettingsResponseTests: XCTestCase {
    func testBasalLimitSettingsResponse() {
        let expected = BasalLimitSettingsResponse(
            basalLimit: 5_000,
            basalLimitDefault: 3_000
        )

        let parsed: BasalLimitSettingsResponse = MessageTester.test(
            "00038b030888130000b80b0000a097",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(5_000, parsed.basalLimit)
        XCTAssertEqual(3_000, parsed.basalLimitDefault)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
