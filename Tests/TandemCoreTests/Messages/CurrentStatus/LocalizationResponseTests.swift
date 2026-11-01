@testable import TandemKit
import XCTest

final class LocalizationResponseTests: XCTestCase {
    func testLocalizationResponse() {
        let expected = LocalizationResponse(glucoseUOM: 0, languageSelected: 0, regionSetting: 2, languagesAvailableBitmask: 1)

        let parsed: LocalizationResponse = MessageTester.test(
            "0004a70407000002010000003a49",
            4,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(parsed.glucoseUOM, 0)
        XCTAssertEqual(parsed.languageSelected, 0)
        XCTAssertEqual(parsed.regionSetting, 2)
        XCTAssertEqual(parsed.languagesAvailableBitmask, 1)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
