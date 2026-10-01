@testable import TandemKit
import XCTest

final class CurrentBasalStatusRequestTests: XCTestCase {
    func testCurrentBasalStatusRequest() {
        let expected = CurrentBasalStatusRequest()

        let parsed: CurrentBasalStatusRequest = MessageTester.test(
            "0003280300a8b6",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
