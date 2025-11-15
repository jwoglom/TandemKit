@testable import TandemCore
import XCTest

final class BolusPermissionRequestTests: XCTestCase {
    func testBolusPermissionRequest_unknown1() {
        MessageTester.initPumpState("6VeDeRAL5DCigGw2", 461_457_713)
        let expected = BolusPermissionRequest()

        let messages = [
            "0134a234181d47811bc64bcd072fc978e4842046",
            "003426b62ba72612b4f04978ac"
        ]
        let parsed: BolusPermissionRequest = MessageTester.test(
            messages[0],
            52,
            2,
            .CONTROL_CHARACTERISTICS,
            expected,
            messages[1]
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
