@testable import TandemKit
import XCTest

final class InsulinStatusResponseTests: XCTestCase {
    func testInsulinStatusResponse() {
        let expected = InsulinStatusResponse(currentInsulinAmount: 0, isEstimate: 0, insulinLowAmount: 35)

        let parsed: InsulinStatusResponse = MessageTester.test(
            "000425040400000023397d",
            4,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.currentInsulinAmount)
        XCTAssertEqual(0, parsed.isEstimate)
        XCTAssertEqual(35, parsed.insulinLowAmount)
    }
}
