@testable import TandemCore
import XCTest

final class SetDexcomG7PairingCodeRequestTests: XCTestCase {
    func testSetG7PairingCodeRequest_code3546() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetDexcomG7PairingCodeRequest(pairingCode: 3546)

        let parsed: SetDexcomG7PairingCodeRequest = MessageTester.test(
            "02f9fcf920da0d000000000000e68cfd1fc0e13b",
            -7,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01f9ff4ae4968d2f256e803caa2487aeea5e8e20",
            "00f9f8"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(3546, parsed.pairingCode)
    }
}
