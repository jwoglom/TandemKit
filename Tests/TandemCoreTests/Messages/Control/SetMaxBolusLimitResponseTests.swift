@testable import TandemKit
import XCTest

final class SetMaxBolusLimitResponseTests: XCTestCase {
    func testSetDeliveryLimitsResponse() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetMaxBolusLimitResponse(status: 0)

        let parsed: SetMaxBolusLimitResponse = MessageTester.test(
            "0061876119007de14920248f42cba27ec99fd6e97b48b5e464ad29691821c4eb",
            97,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
    }
}
