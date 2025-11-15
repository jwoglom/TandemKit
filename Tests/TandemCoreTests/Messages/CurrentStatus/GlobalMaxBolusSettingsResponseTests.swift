@testable import TandemCore
import XCTest

final class GlobalMaxBolusSettingsResponseTests: XCTestCase {
    func testGlobalMaxBolusSettingsResponse() {
        let expected = GlobalMaxBolusSettingsResponse(
            maxBolus: 25000,
            maxBolusDefault: 10000
        )

        let parsed: GlobalMaxBolusSettingsResponse = MessageTester.test(
            "00188d1804a8611027e5ba",
            24,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(25000, parsed.maxBolus)
        XCTAssertEqual(10000, parsed.maxBolusDefault)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
