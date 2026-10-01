@testable import TandemKit
import XCTest

final class ControlIQSleepScheduleResponseTests: XCTestCase {
    private typealias SleepSchedule = ControlIQSleepScheduleResponse.SleepSchedule

    private func assertSchedule(
        _ expected: SleepSchedule,
        _ actual: SleepSchedule,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(expected.enabled, actual.enabled, "enabled", file: file, line: line)
        XCTAssertEqual(expected.activeDays, actual.activeDays, "activeDays", file: file, line: line)
        XCTAssertEqual(expected.startTime, actual.startTime, "startTime", file: file, line: line)
        XCTAssertEqual(expected.endTime, actual.endTime, "endTime", file: file, line: line)
    }

    func testControlIQSleepScheduleResponse1() {
        let everyDay0130To1000 = SleepSchedule(enabled: 1, activeDays: 127, startTime: 90, endTime: 600)
        let disabledDefault2300To0700 = SleepSchedule(enabled: 0, activeDays: 0, startTime: 1380, endTime: 420)
        let expected = ControlIQSleepScheduleResponse(
            schedule0: everyDay0130To1000,
            schedule1: disabledDefault2300To0700,
            schedule2: disabledDefault2300To0700,
            schedule3: disabledDefault2300To0700
        )

        let parsed: ControlIQSleepScheduleResponse = MessageTester.test(
            "00036b0318017f5a00580200006405a40100006405a40100006405a401a330",
            3,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSchedule(everyDay0130To1000, parsed.schedule0)
        assertSchedule(disabledDefault2300To0700, parsed.schedule1)
        assertSchedule(disabledDefault2300To0700, parsed.schedule2)
        assertSchedule(disabledDefault2300To0700, parsed.schedule3)
        XCTAssertEqual(MultiDay.allDays, MultiDay.fromBitmask(parsed.schedule0.activeDays))
    }

    func testControlIQSleepScheduleResponse2() {
        let weekdays2230To1000 = SleepSchedule(
            enabled: 1,
            activeDays: MultiDay.toBitmask([.monday, .tuesday, .wednesday, .thursday, .friday]),
            startTime: MinsTime(hour: 12 + 10, min: 30).encode,
            endTime: MinsTime(hour: 10, min: 0).encode
        )
        let saturday2300To0700 = SleepSchedule(
            enabled: 1,
            activeDays: MultiDay.toBitmask([.saturday]),
            startTime: MinsTime(hour: 12 + 11, min: 0).encode,
            endTime: MinsTime(hour: 7, min: 0).encode
        )
        let hidden2300To0700 = SleepSchedule(
            enabled: 0,
            activeDays: 0,
            startTime: MinsTime(hour: 12 + 11, min: 0).encode,
            endTime: MinsTime(hour: 7, min: 0).encode
        )
        let expected = ControlIQSleepScheduleResponse(
            schedule0: weekdays2230To1000,
            schedule1: saturday2300To0700,
            schedule2: hidden2300To0700,
            schedule3: hidden2300To0700
        )

        let parsed: ControlIQSleepScheduleResponse = MessageTester.test(
            "00046b0418011f4605580201206405a40100006405a40100006405a40109de",
            4,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertSchedule(weekdays2230To1000, parsed.schedule0)
        assertSchedule(saturday2300To0700, parsed.schedule1)
        assertSchedule(hidden2300To0700, parsed.schedule2)
        assertSchedule(hidden2300To0700, parsed.schedule3)
    }
}
