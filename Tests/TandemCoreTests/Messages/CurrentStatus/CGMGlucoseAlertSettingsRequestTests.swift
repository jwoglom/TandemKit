import XCTest
@testable import TandemCore

final class CGMGlucoseAlertSettingsRequestTests: XCTestCase {
    func testCGMGlucoseAlertSettingsRequest() {
        let expected = CGMGlucoseAlertSettingsRequest()

        let parsed: CGMGlucoseAlertSettingsRequest = MessageTester.test(
            "00035a0300c000",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
