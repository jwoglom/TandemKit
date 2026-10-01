@testable import TandemKit
import XCTest

final class StopDexcomCGMSensorSessionRequestTests: XCTestCase {
    func testStopG6SensorSessionRequest_G6Sensor() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = StopDexcomCGMSensorSessionRequest()

        let parsed: StopDexcomCGMSensorSessionRequest = MessageTester.test(
            "015ab45a18810df31fafbfcb967e2fa032a42788",
            90,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "005a3bfb226afd6e404f933dd7"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testStopG6SensorSessionRequest_G7Sensor() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = StopDexcomCGMSensorSessionRequest()

        let parsed: StopDexcomCGMSensorSessionRequest = MessageTester.test(
            "01ecb4ec1892cf5a2085735db9a25e5ae65bf61d",
            -20,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00ece4eb695f3d2116251ef498"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
