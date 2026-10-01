@testable import TandemKit
import XCTest

final class InsulinStatusRequestTests: XCTestCase {
    func testInsulinStatusRequest() {
        let expected = InsulinStatusRequest()

        let parsed: InsulinStatusRequest = MessageTester.test(
            "00042404005e5a",
            4,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
