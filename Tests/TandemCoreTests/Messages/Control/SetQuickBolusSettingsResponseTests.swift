@testable import TandemKit
import XCTest

final class SetQuickBolusSettingsResponseTests: XCTestCase {
    func testSetQuickBolusSettingsResponse() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetQuickBolusSettingsResponse(cargo: Data([0x00]))

        let parsed: SetQuickBolusSettingsResponse = MessageTester.test(
            "004ed34e19002a6ff01fd8f817c3af77277060ce0451da1741ef3caa98d25b8a",
            78,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
    }
}
