@testable import TandemKit
import XCTest

final class SetDexcomG7PairingCodeResponseTests: XCTestCase {
    func testSetG7PairingCodeResponse_success() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetDexcomG7PairingCodeResponse(status: 0)

        let parsed: SetDexcomG7PairingCodeResponse = MessageTester.test(
            "00f9fdf91a00009346fd1f7a5eccab7fe004d6d23a4472643416ebd8b9fe8ff2bf",
            -7,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
    }
}
