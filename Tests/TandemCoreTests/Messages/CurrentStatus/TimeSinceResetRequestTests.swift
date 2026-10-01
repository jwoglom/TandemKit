@testable import TandemKit
import XCTest

final class TimeSinceResetRequestTests: XCTestCase {
    func testTimeSinceResetRequest() {
        let expected = TimeSinceResetRequest()

        let parsed: TimeSinceResetRequest = MessageTester.test(
            "0003360300caee",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
