@testable import TandemKit
import XCTest

final class SetMaxBolusLimitRequestTests: XCTestCase {
    func testSetMaxBolusLimitRequest_20u() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetMaxBolusLimitRequest(maxBolusMilliunits: 20000)

        let parsed: SetMaxBolusLimitRequest = MessageTester.test(
            "016186611a204e92e14920c2f4aee8ca1b7d1960",
            97,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "006175ffd49542eeb8c009ed2022f2"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(20000, parsed.maxBolusMilliunits)
    }
}
