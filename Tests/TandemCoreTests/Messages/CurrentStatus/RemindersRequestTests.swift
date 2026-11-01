@testable import TandemKit
import XCTest

final class RemindersRequestTests: XCTestCase {
    func testRemindersRequest() {
        let expected = RemindersRequest()

        let parsed: RemindersRequest = MessageTester.test(
            "0003580300a06e",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
