@testable import TandemKit
import XCTest

final class LoadStatusRequestTests: XCTestCase {
    func testLoadStatusRequest() {
        let expected = LoadStatusRequest()

        let parsed: LoadStatusRequest = MessageTester.test(
            "0004140400fb9f",
            4,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
