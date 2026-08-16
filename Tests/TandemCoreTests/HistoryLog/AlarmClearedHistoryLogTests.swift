@testable import TandemKit
import XCTest

final class AlarmClearedHistoryLogTests: XCTestCase {
    func testAlarmClearedHistoryLog1() {
        let expected = AlarmClearedHistoryLog(
            // pumpTimeSec, sequenceNum, alarmId
            pumpTimeSec: 580_777_655, sequenceNum: 491_078, alarmId: 18
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "1c10b7f69d22467e070012000000000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testAlarmClearedHistoryLog2() {
        let expected = AlarmClearedHistoryLog(
            // pumpTimeSec, sequenceNum, alarmId
            pumpTimeSec: 580_777_655, sequenceNum: 491_077, alarmId: 23
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "1c10b7f69d22457e070017000000000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
