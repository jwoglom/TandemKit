@testable import TandemKit
import XCTest

final class ChangeTimeDateResponseTests: XCTestCase {
    func testChangeTimeDateResponse() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = ChangeTimeDateResponse(status: 0)

        let parsed: ChangeTimeDateResponse = MessageTester.test(
            "0043d743190030173920f8632cafa89dbda3879449357f9242636693d60cf4fb",
            67,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
    }
}
