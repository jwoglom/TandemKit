import XCTest
@testable import TandemCore

final class AlarmStatusResponseTests: XCTestCase {
    func testAlarmStatusEmptyResponse() {
        let expected = AlarmStatusResponse(intMap: 0)

        let parsed: AlarmStatusResponse = MessageTester.test(
            "000347030800000000000000005721",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(0, parsed.intMap)
        XCTAssertTrue(parsed.alarms.isEmpty)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testAlarmStatusPumpResetAndResume() {
        let pumpResetBit = UInt64(1) << UInt64(AlarmStatusResponse.AlarmResponseType.PUMP_RESET_ALARM.rawValue)
        let resumePumpBit = UInt64(1) << UInt64(AlarmStatusResponse.AlarmResponseType.RESUME_PUMP_ALARM2.rawValue)
        let bitmask = pumpResetBit | resumePumpBit
        let expected = AlarmStatusResponse(intMap: bitmask)

        let parsed: AlarmStatusResponse = MessageTester.test(
            "000c470c0808008000000000001cbd",
            12,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(bitmask, parsed.intMap)
        XCTAssertEqual(expected.alarms, parsed.alarms)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
