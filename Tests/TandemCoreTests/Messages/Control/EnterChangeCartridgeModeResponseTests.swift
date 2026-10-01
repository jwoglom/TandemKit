@testable import TandemKit
import XCTest

final class EnterChangeCartridgeModeResponseTests: XCTestCase {
    func testChangeCartridgeResponse_2() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = EnterChangeCartridgeModeResponse(status: 0)

        let parsed: EnterChangeCartridgeModeResponse = MessageTester.test(
            "003691361900e2cd272051bfc76d9666fb6bbe8b89627199c182617b1f6fe440",
            54,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
    }
}
