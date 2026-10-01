@testable import TandemKit
import XCTest

final class CurrentBolusStatusRequestTests: XCTestCase {
    func testCurrentBolusStatusRequest() {
        let expected = CurrentBolusStatusRequest()

        let parsed: CurrentBolusStatusRequest = MessageTester.test(
            "00032c0300686a",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
