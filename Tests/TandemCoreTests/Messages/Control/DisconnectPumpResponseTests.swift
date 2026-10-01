@testable import TandemKit
import XCTest

final class DisconnectPumpResponseTests: XCTestCase {
    func testDisconnectPumpResponse() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = DisconnectPumpResponse(status: 0)

        let parsed: DisconnectPumpResponse = MessageTester.test(
            "00debfde1900000000003fad35823cf021e2dad26d3f485cd5b4557dfe88ef21",
            -34,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
    }
}
