@testable import TandemKit
import XCTest

final class ExitFillTubingModeResponseTests: XCTestCase {
    func testExitFillTubingModeResponse() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = ExitFillTubingModeResponse(status: 0)

        let parsed: ExitFillTubingModeResponse = MessageTester.test(
            "009197911900aec8402021f71d880600f40c8f92f96bbca87dbea12d73ad213b",
            -111,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
    }
}
