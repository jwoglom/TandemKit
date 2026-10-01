@testable import TandemKit
import XCTest

final class StopDexcomCGMSensorSessionResponseTests: XCTestCase {
    func testStopG6SensorSessionResponse() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = StopDexcomCGMSensorSessionResponse(status: 0)

        let parsed: StopDexcomCGMSensorSessionResponse = MessageTester.test(
            "005ab55a19002cc7f21f7fc48fc9d4bfe3feca73675911cca9f1b3a96caba40c",
            90,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
    }
}
