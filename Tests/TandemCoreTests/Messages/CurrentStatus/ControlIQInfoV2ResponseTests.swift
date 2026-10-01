@testable import TandemKit
import XCTest

final class ControlIQInfoV2ResponseTests: XCTestCase {
    func testControlIQInfoV2Response_old() {
        let expected = ControlIQInfoV2Response(
            closedLoopEnabled: true,
            weight: 150,
            weightUnit: 1,
            totalDailyInsulin: 75,
            currentUserModeType: 1,
            byte6: 0,
            byte7: 1,
            byte8: 1,
            controlStateType: 3,
            exerciseChoice: 0,
            exerciseDuration: 0,
            exerciseTimeRemaining: 0
        )

        let parsed: ControlIQInfoV2Response = MessageTester.test(
            "000cb30c13019600014b01000101030000000000000000002d45",
            12,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertTrue(parsed.closedLoopEnabled)
        XCTAssertEqual(150, parsed.weight)
        XCTAssertEqual(.pounds, parsed.weightUnit)
        XCTAssertEqual(75, parsed.totalDailyInsulin)
        XCTAssertEqual(.sleep, parsed.currentUserModeType)
        XCTAssertEqual(0, parsed.byte6)
        XCTAssertEqual(1, parsed.byte7)
        XCTAssertEqual(1, parsed.byte8)
        XCTAssertEqual(3, parsed.controlStateType)
        XCTAssertEqual(0, parsed.exerciseChoice)
        XCTAssertEqual(0, parsed.exerciseDuration)
        XCTAssertEqual(0, parsed.exerciseTimeRemaining)
    }

    func testControlIQInfoV2Response_standard() {
        let expected = ControlIQInfoV2Response(
            closedLoopEnabled: true,
            weight: 150,
            weightUnit: 1,
            totalDailyInsulin: 75,
            currentUserModeType: 0,
            byte6: 1,
            byte7: 2,
            byte8: 0,
            controlStateType: 3,
            exerciseChoice: 0,
            exerciseDuration: 0,
            exerciseTimeRemaining: 0
        )

        let parsed: ControlIQInfoV2Response = MessageTester.test(
            "005ab35a13019600014b000102000300000000000000000034ef",
            90,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertTrue(parsed.closedLoopEnabled)
        XCTAssertEqual(150, parsed.weight)
        XCTAssertEqual(.pounds, parsed.weightUnit)
        XCTAssertEqual(75, parsed.totalDailyInsulin)
        XCTAssertEqual(.standard, parsed.currentUserModeType)
        XCTAssertEqual(1, parsed.byte6)
        XCTAssertEqual(2, parsed.byte7)
        XCTAssertEqual(0, parsed.byte8)
        XCTAssertEqual(3, parsed.controlStateType)
        XCTAssertEqual(0, parsed.exerciseChoice)
        XCTAssertEqual(0, parsed.exerciseDuration)
        XCTAssertEqual(0, parsed.exerciseTimeRemaining)
    }

    func testControlIQInfoV2Response_sleep() {
        let expected = ControlIQInfoV2Response(
            closedLoopEnabled: true,
            weight: 150,
            weightUnit: 1,
            totalDailyInsulin: 75,
            currentUserModeType: 1,
            byte6: 0,
            byte7: 1,
            byte8: 0,
            controlStateType: 3,
            exerciseChoice: 0,
            exerciseDuration: 0,
            exerciseTimeRemaining: 0
        )

        let parsed: ControlIQInfoV2Response = MessageTester.test(
            "0024b32413019600014b0100010003000000000000000000a95f",
            36,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertTrue(parsed.closedLoopEnabled)
        XCTAssertEqual(150, parsed.weight)
        XCTAssertEqual(.pounds, parsed.weightUnit)
        XCTAssertEqual(75, parsed.totalDailyInsulin)
        XCTAssertEqual(.sleep, parsed.currentUserModeType)
        XCTAssertEqual(0, parsed.byte6)
        XCTAssertEqual(1, parsed.byte7)
        XCTAssertEqual(0, parsed.byte8)
        XCTAssertEqual(3, parsed.controlStateType)
        XCTAssertEqual(0, parsed.exerciseChoice)
        XCTAssertEqual(0, parsed.exerciseDuration)
        XCTAssertEqual(0, parsed.exerciseTimeRemaining)
    }
}
