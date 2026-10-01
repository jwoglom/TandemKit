@testable import TandemKit
import XCTest

final class SetSleepScheduleRequestTests: XCTestCase {
    func testSetSleepScheduleRequest_set0_rawBytes() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1_905_836)
        let expected = SetSleepScheduleRequest(cargo: Data([0x00, 0x01, 0x7F, 0x00, 0x00, 0x9F, 0x05, 0x03]))

        let parsed: SetSleepScheduleRequest = MessageTester.test(
            "02a2cea22000017f00009f0503ff978b1e828836",
            -94,
            3,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01a222d3b77a25443cc291be989dc841df1a8a75",
            "00a266"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.slot)
        XCTAssertEqual(1, parsed.schedule.enabled)
        XCTAssertEqual(MultiDay.allDays, MultiDay.fromBitmask(parsed.schedule.activeDays))
        XCTAssertEqual(MinsTime(0), MinsTime(parsed.schedule.startTime))
        XCTAssertEqual(MinsTime(hour: 23, min: 59), MinsTime(parsed.schedule.endTime))
        XCTAssertEqual(3, parsed.flag)
    }

    func testSetSleepScheduleRequest_disable0() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1_905_836)
        let expected = SetSleepScheduleRequest(cargo: Data([0x00, 0x00, 0x7F, 0x00, 0x00, 0x9F, 0x05, 0x03]))

        let parsed: SetSleepScheduleRequest = MessageTester.test(
            "02abceab2000007f00009f050311988b1ef9651b",
            -85,
            3,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01abc15275490acd94a3416d8cfc038cd7ff461a",
            "00ab0c"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.slot)
        XCTAssertEqual(0, parsed.schedule.enabled)
        XCTAssertEqual(MultiDay.allDays, MultiDay.fromBitmask(parsed.schedule.activeDays))
        XCTAssertEqual(MinsTime(0), MinsTime(parsed.schedule.startTime))
        XCTAssertEqual(MinsTime(hour: 23, min: 59), MinsTime(parsed.schedule.endTime))
        XCTAssertEqual(3, parsed.flag)
    }
}
