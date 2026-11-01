@testable import TandemKit
import XCTest

final class LocalizationRequestTests: XCTestCase {
    func testLocalizationRequest() {
        let expected = LocalizationRequest()

        let parsed: LocalizationRequest = MessageTester.test(
            "0004a60400640f",
            4,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
