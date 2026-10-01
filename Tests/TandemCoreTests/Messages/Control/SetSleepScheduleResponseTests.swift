@testable import TandemKit
import XCTest

final class SetSleepScheduleResponseTests: XCTestCase {
    func testSetSleepScheduleResponse_mobi() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1_905_836)
        let expected = SetSleepScheduleResponse(cargo: Data([0x00]))

        let parsed: SetSleepScheduleResponse = MessageTester.test(
            "00a2cfa2190099438b1e67bcbb479d9ba61f4ce07e3bfebf2305b87092ed11b4",
            -94,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
    }
}
