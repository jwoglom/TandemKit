@testable import TandemKit
import XCTest

final class DismissNotificationResponseTests: XCTestCase {
    func testDismissNotificationResponse() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = DismissNotificationResponse(status: 0)

        let parsed: DismissNotificationResponse = MessageTester.test(
            "001eb91e19003ba8f21fe16f0c1b71446a28fadaa20c0304576230243bfe5a5d",
            30,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
    }
}
