@testable import TandemKit
import XCTest

final class HighestAamRequestTests: XCTestCase {
    func testHighestAamRequest() {
        let expected = HighestAamRequest()

        let parsed: HighestAamRequest = MessageTester.test(
            "0007780700a224",
            7,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
