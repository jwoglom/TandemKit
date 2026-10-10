@testable import TandemKit
import XCTest

final class ControlIQIOBRequestTests: XCTestCase {
    func testControlIQIOBRequest() {
        let expected = ControlIQIOBRequest()

        let parsed: ControlIQIOBRequest = MessageTester.test(
            "00046c040052ee",
            4,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
