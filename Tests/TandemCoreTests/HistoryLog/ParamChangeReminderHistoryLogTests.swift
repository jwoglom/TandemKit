@testable import TandemKit
import XCTest

final class ParamChangeReminderHistoryLogTests: XCTestCase {
    func testParamChangeReminderHistoryLog1() {
        // pumpTimeSec, sequenceNum, modification, reminderId, status, enable, frequencyMinutes, startTime, endTime, activeDays
        let expected = ParamChangeReminderHistoryLog(
            pumpTimeSec: 580_601_544,
            sequenceNum: 483_936,
            modification: 1,
            reminderId: 2,
            status: 3,
            enable: 1,
            frequencyMinutes: 1380,
            startTime: 0,
            endTime: 0,
            activeDays: 0
        ).withHeaderHighNibble(1)

        let parsedRes = HistoryLogMessageTester.testSingle(
            "6010c8469b226062070001020301640500000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
    }

    func testParamChangeReminderHistoryLog2() {
        // pumpTimeSec, sequenceNum, modification, reminderId, status, enable, frequencyMinutes, startTime, endTime, activeDays
        let expected = ParamChangeReminderHistoryLog(
            pumpTimeSec: 580_601_544,
            sequenceNum: 483_935,
            modification: 0,
            reminderId: 2,
            status: 3,
            enable: 1,
            frequencyMinutes: 1380,
            startTime: 0,
            endTime: 0,
            activeDays: 0
        ).withHeaderHighNibble(1)

        let parsedRes = HistoryLogMessageTester.testSingle(
            "6010c8469b225f62070000020301640500000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
    }
}
