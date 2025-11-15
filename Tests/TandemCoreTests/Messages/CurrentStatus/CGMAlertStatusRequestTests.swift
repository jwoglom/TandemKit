import XCTest
@testable import TandemCore

final class CGMAlertStatusRequestTests: XCTestCase {
    func testCGMAlertStatusRequest() {
        let expected = CGMAlertStatusRequest()

        let parsed: CGMAlertStatusRequest = MessageTester.test(
            "00034a0300a343",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
