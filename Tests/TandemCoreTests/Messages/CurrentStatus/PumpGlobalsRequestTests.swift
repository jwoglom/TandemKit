@testable import TandemKit
import XCTest

final class PumpGlobalsRequestTests: XCTestCase {
    func testPumpGlobalsRequest() {
        let expected = PumpGlobalsRequest()

        let parsed: PumpGlobalsRequest = MessageTester.test(
            "0003560300a175",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
