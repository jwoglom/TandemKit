@testable import TandemKit
import XCTest

final class ControlIQInfoV1ResponseTests: XCTestCase {
    func testControlIQInfoResponsePounds() {
        let expected = ControlIQInfoV1Response(
            closedLoopEnabled: true,
            weight: 150,
            weightUnit: 1,
            totalDailyInsulin: 75,
            currentUserModeType: 0,
            byte6: 0,
            byte7: 0,
            byte8: 4,
            controlStateType: 0
        )

        let parsed: ControlIQInfoV1Response = MessageTester.test(
            "000369030a019600014b0000000400b912",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertTrue(parsed.closedLoopEnabled)
        XCTAssertEqual(150, parsed.weight)
        XCTAssertEqual(1, parsed.weightUnitRaw)
        XCTAssertEqual(.pounds, parsed.weightUnit)
        XCTAssertEqual(75, parsed.totalDailyInsulin)
        XCTAssertEqual(.standard, parsed.currentUserModeType)
        XCTAssertEqual(0, parsed.byte6)
        XCTAssertEqual(0, parsed.byte7)
        XCTAssertEqual(4, parsed.byte8)
        XCTAssertEqual(0, parsed.controlStateType)
    }

    func testControlIQInfoResponseKilograms() {
        let expected = ControlIQInfoV1Response(
            closedLoopEnabled: true,
            weight: 140,
            weightUnit: 2,
            totalDailyInsulin: 75,
            currentUserModeType: 0,
            byte6: 0,
            byte7: 0,
            byte8: 4,
            controlStateType: 0
        )

        let parsed: ControlIQInfoV1Response = MessageTester.test(
            "000469040a018c00024b0000000400167e",
            4,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertTrue(parsed.closedLoopEnabled)
        XCTAssertEqual(140, parsed.weight)
        XCTAssertEqual(2, parsed.weightUnitRaw)
        XCTAssertEqual(75, parsed.totalDailyInsulin)
        XCTAssertEqual(.standard, parsed.currentUserModeType)
        XCTAssertEqual(4, parsed.byte8)
        XCTAssertEqual(0, parsed.controlStateType)
    }
}
