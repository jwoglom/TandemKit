@testable import TandemCore
import XCTest

final class CGMRateAlertSettingsRequestTests: XCTestCase {
    func testCGMRateAlertSettingsRequest() {
        let expected = CGMRateAlertSettingsRequest()

        let parsed: CGMRateAlertSettingsRequest = MessageTester.test(
            "00045c0400f72b",
            4,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
