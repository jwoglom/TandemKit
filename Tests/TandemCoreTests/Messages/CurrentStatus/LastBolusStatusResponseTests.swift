@testable import TandemKit
import XCTest

final class LastBolusStatusResponseTests: XCTestCase {
    func testLastBolusStatusResponse() {
        let expected = LastBolusStatusResponse(
            status: 1,
            bolusId: 10690,
            timestamp: 463_703_230,
            deliveredVolume: 200,
            bolusStatusId: 3,
            bolusSourceId: 8,
            bolusTypeBitmask: 8,
            extendedBolusDuration: 0,
            unknown: Data(count: 2)
        )

        let parsed: LastBolusStatusResponse = MessageTester.test(
            "000531051401c2290000be8ca31bc800000003080800000000bc1f",
            5,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(1, parsed.status)
        XCTAssertEqual(10690, parsed.bolusId)
        XCTAssertEqual(463_703_230, parsed.timestamp)
        XCTAssertEqual(200, parsed.deliveredVolume)
        XCTAssertEqual(3, parsed.bolusStatusId)
        XCTAssertEqual(8, parsed.bolusSourceId)
        XCTAssertEqual(8, parsed.bolusTypeBitmask)
        XCTAssertEqual(0, parsed.extendedBolusDuration)
        XCTAssertEqual(Data(count: 2), parsed.unknown)
        XCTAssertEqual(.bluetoothRemoteBolus, parsed.bolusSource)
    }
}
