@testable import TandemKit
import XCTest

final class SetPumpAlertSnoozeResponseTests: XCTestCase {
    func testSetPumpAlertSnoozeResponse() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetPumpAlertSnoozeResponse(status: 0)

        let parsed: SetPumpAlertSnoozeResponse = MessageTester.test(
            "0031d5311900ba80682053558873893a6be84fccd0aa1a79beb7a1eb118a9cb8",
            49,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
    }
}
