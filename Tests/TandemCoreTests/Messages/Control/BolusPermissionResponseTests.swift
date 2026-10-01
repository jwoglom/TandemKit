@testable import TandemKit
import XCTest

final class BolusPermissionResponseTests: XCTestCase {
    func testBolusPermissionResponse() {
        MessageTester.initPumpState("6VeDeRAL5DCigGw2", 461_510_588)
        let expected = BolusPermissionResponse(status: 0, bolusId: 10650, nackReasonId: 0)

        let parsed: BolusPermissionResponse = MessageTester.test(
            "00efa3ef1e009a29000000c317821b8a7f9a9bd41e220a20856446e2ff9c69df60ab62987c",
            -17,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
        XCTAssertEqual(10650, parsed.bolusId)
        XCTAssertEqual(0, parsed.nackReasonId)
    }

    func testBolusPermissionResponse_disallowed_openOnPump() {
        MessageTester.initPumpState("6VeDeRAL5DCigGw2", 461_634_498)
        let expected = BolusPermissionResponse(status: 1, bolusId: 0, nackReasonId: 3)

        let parsed: BolusPermissionResponse = MessageTester.test(
            "0004a3041e010000000003dcfb831b6decc93831b2a85debe64b35493ac44a60652af9e0a7",
            4,
            2,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(1, parsed.status)
        XCTAssertEqual(0, parsed.bolusId)
        XCTAssertEqual(3, parsed.nackReasonId)
        XCTAssertEqual(.pumpHasPermission, parsed.nackReason)
    }

    func testBolusPermissionResponse_disallowed_deliveriesStopped() {
        MessageTester.initPumpState("6VeDeRAL5DCigGw2", 461_634_831)
        let expected = BolusPermissionResponse(status: 1, bolusId: 0, nackReasonId: 1)

        let parsed: BolusPermissionResponse = MessageTester.test(
            "0004a3041e01000000000115fd831ba02d482bc5e45a7aab99f79ce1fd55f57b6828467fce",
            4,
            2,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(1, parsed.status)
        XCTAssertEqual(0, parsed.bolusId)
        XCTAssertEqual(1, parsed.nackReasonId)
        XCTAssertEqual(.invalidPumpingState, parsed.nackReason)
    }
}
