@testable import TandemCore
import XCTest

final class AlertStatusRequestTests: XCTestCase {
    func testAlertStatusRequest() {
        let expected = AlertStatusRequest()

        let parsed: AlertStatusRequest = MessageTester.test(
            "0003440300a258",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
