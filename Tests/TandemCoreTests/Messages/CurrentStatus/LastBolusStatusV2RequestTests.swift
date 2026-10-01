@testable import TandemKit
import XCTest

final class LastBolusStatusV2RequestTests: XCTestCase {
    func testLastBolusStatusV2Request() {
        let expected = LastBolusStatusV2Request()

        let parsed: LastBolusStatusV2Request = MessageTester.test(
            "0004a404000461",
            4,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
