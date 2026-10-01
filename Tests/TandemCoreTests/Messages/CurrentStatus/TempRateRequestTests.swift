@testable import TandemKit
import XCTest

final class TempRateRequestTests: XCTestCase {
    func testTempRateRequest() {
        let expected = TempRateRequest()

        let parsed: TempRateRequest = MessageTester.test(
            "00032a0300c8d8",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
