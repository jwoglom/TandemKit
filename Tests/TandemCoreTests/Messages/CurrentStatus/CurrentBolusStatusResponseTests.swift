@testable import TandemKit
import XCTest

final class CurrentBolusStatusResponseTests: XCTestCase {
    func testCurrentBolusStatusResponseEmpty() {
        let expected = CurrentBolusStatusResponse(
            statusId: 0,
            bolusId: 0,
            timestamp: 0,
            requestedVolume: 0,
            bolusSourceId: 0,
            bolusTypeBitmask: 0
        )

        let parsed: CurrentBolusStatusResponse = MessageTester.test(
            "00032d030f000000000000000000000000000000b109",
            3,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(.alreadyDeliveredOrInvalid, parsed.status)
        XCTAssertEqual(0, parsed.bolusId)
        XCTAssertEqual(0, parsed.timestamp)
        XCTAssertEqual(0, parsed.requestedVolume)
        XCTAssertEqual(0, parsed.bolusSourceId)
        XCTAssertEqual(0, parsed.bolusTypeBitmask)
        XCTAssertFalse(parsed.isValid)
    }
}
