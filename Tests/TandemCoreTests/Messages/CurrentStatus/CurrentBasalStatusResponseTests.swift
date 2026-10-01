@testable import TandemKit
import XCTest

final class CurrentBasalStatusResponseTests: XCTestCase {
    func testCurrentBasalStatusResponse() {
        let expected = CurrentBasalStatusResponse(
            profileBasalRate: 800,
            currentBasalRate: 0,
            basalModifiedBitmask: 1
        )

        let parsed: CurrentBasalStatusResponse = MessageTester.test(
            "0003290309200300000000000001d8d0",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0.8, parsed.profileBasalRate)
        XCTAssertEqual(0, parsed.currentBasalRate)
        XCTAssertEqual(1, parsed.basalModifiedBitmask)
        XCTAssertEqual(.suspend, parsed.basalType)
    }
}
