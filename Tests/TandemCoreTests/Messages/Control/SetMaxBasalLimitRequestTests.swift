@testable import TandemKit
import XCTest

final class SetMaxBasalLimitRequestTests: XCTestCase {
    func testSetMaxBasalLimitRequest_5u() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetMaxBasalLimitRequest(maxHourlyBasalMilliunits: 5000)

        let parsed: SetMaxBasalLimitRequest = MessageTester.test(
            "017588751c881300003ee34920d580d42e829ec9",
            117,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00754d9fdc7a1f65f92b9b1f7c227bbb56"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(5000, parsed.maxHourlyBasalMilliunits)
    }
}
