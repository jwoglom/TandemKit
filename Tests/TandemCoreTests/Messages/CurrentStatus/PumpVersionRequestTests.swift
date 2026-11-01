@testable import TandemKit
import XCTest

final class PumpVersionRequestTests: XCTestCase {
    func testPumpVersionRequest() {
        let expected = PumpVersionRequest()

        let parsed: PumpVersionRequest = MessageTester.test(
            "0003540300c11b",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
