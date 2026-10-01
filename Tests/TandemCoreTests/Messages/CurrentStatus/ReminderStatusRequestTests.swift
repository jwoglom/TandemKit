@testable import TandemKit
import XCTest

final class ReminderStatusRequestTests: XCTestCase {
    func testReminderStatusRequest() {
        let expected = ReminderStatusRequest()

        let parsed: ReminderStatusRequest = MessageTester.test(
            "0003480300c32d",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
