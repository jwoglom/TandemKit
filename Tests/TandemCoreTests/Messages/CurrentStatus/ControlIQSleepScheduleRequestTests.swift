@testable import TandemKit
import XCTest

final class ControlIQSleepScheduleRequestTests: XCTestCase {
    func testControlIQSleepScheduleRequest() {
        let expected = ControlIQSleepScheduleRequest()

        let parsed: ControlIQSleepScheduleRequest = MessageTester.test(
            "00036a030065c5",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
