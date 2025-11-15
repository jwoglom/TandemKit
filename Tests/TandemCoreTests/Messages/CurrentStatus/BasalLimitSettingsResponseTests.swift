@testable import TandemCore
import XCTest

final class BasalLimitSettingsResponseTests: XCTestCase {
    func testBasalLimitSettingsResponse() {
        let expected = BasalLimitSettingsResponse(
            basalLimit: 5000,
            basalLimitDefault: 3000
        )

        let parsed: BasalLimitSettingsResponse = MessageTester.test(
            "00038b030888130000b80b0000a097",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(5000, parsed.basalLimit)
        XCTAssertEqual(3000, parsed.basalLimitDefault)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
