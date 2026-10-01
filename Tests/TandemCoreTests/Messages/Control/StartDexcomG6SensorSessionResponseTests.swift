@testable import TandemKit
import XCTest

final class StartDexcomG6SensorSessionResponseTests: XCTestCase {
    func testStartG6SensorSessionResponse() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = StartDexcomG6SensorSessionResponse(status: 0)

        let parsed: StartDexcomG6SensorSessionResponse = MessageTester.test(
            "002eb32e1900cbc3f21f0a67a11d39b6d34d4936e72c6cfb468c9a4b768c6115",
            46,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
    }
}
