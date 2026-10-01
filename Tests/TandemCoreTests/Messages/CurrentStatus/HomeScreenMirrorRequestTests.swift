@testable import TandemKit
import XCTest

final class HomeScreenMirrorRequestTests: XCTestCase {
    func testHomeScreenMirrorRequest() {
        let expected = HomeScreenMirrorRequest()

        let parsed: HomeScreenMirrorRequest = MessageTester.test(
            "0003380300cbf5",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
