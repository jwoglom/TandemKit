@testable import TandemKit
import XCTest

final class PumpSettingsRequestTests: XCTestCase {
    func testPumpSettingsRequest() {
        let expected = PumpSettingsRequest()

        let parsed: PumpSettingsRequest = MessageTester.test(
            "0004520400f630",
            4,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
