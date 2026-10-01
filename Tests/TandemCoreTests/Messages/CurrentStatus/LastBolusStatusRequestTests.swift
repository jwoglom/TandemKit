@testable import TandemKit
import XCTest

final class LastBolusStatusRequestTests: XCTestCase {
    func testLastBolusStatusRequest() {
        let expected = LastBolusStatusRequest()

        let parsed: LastBolusStatusRequest = MessageTester.test(
            "0005300500ccf6",
            5,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
