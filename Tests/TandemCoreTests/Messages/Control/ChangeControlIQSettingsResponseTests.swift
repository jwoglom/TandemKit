@testable import TandemKit
import XCTest

final class ChangeControlIQSettingsResponseTests: XCTestCase {
    func testChangeControlIQSettingsResponse() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = ChangeControlIQSettingsResponse(cargo: Data([0x00, 0x00, 0x00]))

        let parsed: ChangeControlIQSettingsResponse = MessageTester.test(
            "005ccb5c1b000000d9a3ee1f799d9f28e8a6759fed2cb0fafeffdea01a2b0cf56bb0",
            92,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
