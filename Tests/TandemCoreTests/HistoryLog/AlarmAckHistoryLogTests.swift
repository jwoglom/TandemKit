@testable import TandemKit
import XCTest

final class AlarmAckHistoryLogTests: XCTestCase {
    func testAlarmAckHistoryLog1() {
        let expected = AlarmAckHistoryLog(
            // pumpTimeSec, sequenceNum, alarmId
            pumpTimeSec: 580_777_655, sequenceNum: 491_076, alarmId: 18
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "0810b7f69d22447e070012000000000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testAlarmAckHistoryLog2() {
        let expected = AlarmAckHistoryLog(
            // pumpTimeSec, sequenceNum, alarmId
            pumpTimeSec: 579_744_825, sequenceNum: 448_164, alarmId: 18
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "081039348e22a4d6060012000000000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
