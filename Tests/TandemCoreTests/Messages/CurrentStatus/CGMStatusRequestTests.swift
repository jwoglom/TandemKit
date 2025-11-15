@testable import TandemCore
import XCTest

final class CGMStatusRequestTests: XCTestCase {
    func testCGMStatusRequest() {
        let expected = CGMStatusRequest()

        let parsed: CGMStatusRequest = MessageTester.test(
            "000350030001c7",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
