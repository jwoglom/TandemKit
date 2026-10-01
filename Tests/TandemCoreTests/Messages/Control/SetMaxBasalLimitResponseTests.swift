@testable import TandemKit
import XCTest

final class SetMaxBasalLimitResponseTests: XCTestCase {
    func testSetMaxBasalLimitResponse() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetMaxBasalLimitResponse(status: 0)

        let parsed: SetMaxBasalLimitResponse = MessageTester.test(
            "00758975190029e34920e1e6145d9ec4ced8f764873318b61dac15b7e3fee55e",
            117,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
    }
}
