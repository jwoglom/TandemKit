import XCTest
@testable import TandemCore

final class ChangeControlIQSettingsRequestTests: XCTestCase {
    func testChangeControlIQSettingsRequest_turnOn_150lbs_75tdu() {
        MessageTester.initPumpState("", 0)
        let expected = ChangeControlIQSettingsRequest(enabled: true, weightLbs: 150, totalDailyInsulinUnits: 75)

        let parsed: ChangeControlIQSettingsRequest = MessageTester.test(
            "0157ca571e019600014b0127eaee1fe2a83a5338",
            87,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00578298cbe960ee83e35b3d3fde85b38d7eba"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertTrue(parsed.enabled)
        XCTAssertEqual(150, parsed.weightLbs)
        XCTAssertEqual(75, parsed.totalDailyInsulinUnits)
    }

    func testChangeControlIQSettingsRequest_turnOff_150lbs_75tdu() {
        MessageTester.initPumpState("", 0)
        let expected = ChangeControlIQSettingsRequest(enabled: false, weightLbs: 150, totalDailyInsulinUnits: 75)

        let parsed: ChangeControlIQSettingsRequest = MessageTester.test(
            "015cca5c1e009600014b012ceaee1f556e63dee5",
            92,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "005ce9516bf5a6d77eb884dc557e841663bea5"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertFalse(parsed.enabled)
        XCTAssertEqual(150, parsed.weightLbs)
        XCTAssertEqual(75, parsed.totalDailyInsulinUnits)
    }
}
