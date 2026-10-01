@testable import TandemKit
import XCTest

final class ControlIQInfoV1RequestTests: XCTestCase {
    func testControlIQInfoRequest() {
        let expected = ControlIQInfoV1Request()

        let parsed: ControlIQInfoV1Request = MessageTester.test(
            "000368030005ab",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
