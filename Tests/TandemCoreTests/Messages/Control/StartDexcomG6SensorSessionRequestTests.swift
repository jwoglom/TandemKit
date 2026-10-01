@testable import TandemKit
import XCTest

final class StartDexcomG6SensorSessionRequestTests: XCTestCase {
    func testStartG6SensorSessionRequest_code9311() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = StartDexcomG6SensorSessionRequest(sensorCode: 9311)

        let parsed: StartDexcomG6SensorSessionRequest = MessageTester.test(
            "012eb22e1a5f24210af31f6806b4cc57d79bb047",
            46,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "002e5f4261e734aaa05941d57f7901"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(9311, parsed.sensorCode)
    }
}
