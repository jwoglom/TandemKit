@testable import TandemKit
import XCTest

final class EnterFillTubingModeResponseTests: XCTestCase {
    func testEnterFillTubingModeResponse() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = EnterFillTubingModeResponse(status: 0)

        let parsed: EnterFillTubingModeResponse = MessageTester.test(
            "007a957a1900fea3ee1fe559e33c9fdc97594748e9c9631ee2db4458683f3412",
            122,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
    }
}
