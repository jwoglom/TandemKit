@testable import TandemCore
import XCTest

final class CGMHardwareInfoRequestTests: XCTestCase {
    func testCGMHardwareInfoRequest() {
        let expected = CGMHardwareInfoRequest()

        let parsed: CGMHardwareInfoRequest = MessageTester.test(
            "0004600400339b",
            4,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
