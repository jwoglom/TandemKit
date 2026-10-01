@testable import TandemKit
import XCTest

final class InitiateBolusResponseTests: XCTestCase {
    func testInitiateBolusResponse_ID10650() {
        MessageTester.initPumpState("6VeDeRAL5DCigGw2", 461_510_642)
        let expected = InitiateBolusResponse(status: 0, bolusId: 10650, statusTypeId: 0)

        let parsed: InitiateBolusResponse = MessageTester.test(
            "00399f391e009a29000000f717821b19f3e1e5f2e0950d2ede3572f325e6f400b019c37ce3",
            57,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
        XCTAssertEqual(10650, parsed.bolusId)
        XCTAssertEqual(0, parsed.statusTypeId)
    }

    func testInitiateBolusResponse_ID10652_013u_13g_carbs_142mgdl() {
        MessageTester.initPumpState("6VeDeRAL5DCigGw2", 461_589_180)
        let expected = InitiateBolusResponse(status: 0, bolusId: 10652, statusTypeId: 0)

        let parsed: InitiateBolusResponse = MessageTester.test(
            "003e9f3e1e009c29000000e64a831b494e667a54ee8b35042d93ad4af8c612963d76b86f60",
            62,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
        XCTAssertEqual(10652, parsed.bolusId)
        XCTAssertEqual(0, parsed.statusTypeId)
    }
}
