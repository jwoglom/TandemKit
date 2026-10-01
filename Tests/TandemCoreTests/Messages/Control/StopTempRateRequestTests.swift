@testable import TandemKit
import XCTest

final class StopTempRateRequestTests: XCTestCase {
    func testStopTempRateRequest() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1_906_112)
        let expected = StopTempRateRequest()

        let parsed: StopTempRateRequest = MessageTester.test(
            "012ca62c182c998b1e92605660ce66863620411d",
            44,
            2,
            .CONTROL_CHARACTERISTICS,
            expected,
            "002c0d420615066cb0f317766c"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testStopTempRateRequest_2() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1_906_112)
        let expected = StopTempRateRequest()

        let parsed: StopTempRateRequest = MessageTester.test(
            "0151a651181eeaee1ffbff278a74c8692c24136b",
            81,
            2,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00513e473b93df7f77e6fb867d"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
