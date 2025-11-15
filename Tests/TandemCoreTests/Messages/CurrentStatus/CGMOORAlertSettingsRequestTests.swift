@testable import TandemCore
import XCTest

final class CGMOORAlertSettingsRequestTests: XCTestCase {
    func testCGMOORAlertSettingsRequest() {
        let expected = CGMOORAlertSettingsRequest()

        let parsed: CGMOORAlertSettingsRequest = MessageTester.test(
            "00035e030000dc",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
