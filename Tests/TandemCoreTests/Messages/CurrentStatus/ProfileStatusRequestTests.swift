@testable import TandemKit
import XCTest

final class ProfileStatusRequestTests: XCTestCase {
    func testProfileStatusRequest() {
        let expected = ProfileStatusRequest()

        let parsed: ProfileStatusRequest = MessageTester.test(
            "00033e03006b47",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
