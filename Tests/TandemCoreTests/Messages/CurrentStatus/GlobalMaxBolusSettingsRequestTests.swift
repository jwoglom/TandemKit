import XCTest
@testable import TandemCore

final class GlobalMaxBolusSettingsRequestTests: XCTestCase {
    func testGlobalMaxBolusSettingsRequest() {
        let expected = GlobalMaxBolusSettingsRequest()

        let parsed: GlobalMaxBolusSettingsRequest = MessageTester.test(
            "00038c0300f4d7",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
