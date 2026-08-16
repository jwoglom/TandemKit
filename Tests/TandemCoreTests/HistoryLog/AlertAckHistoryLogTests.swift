@testable import TandemKit
import XCTest

final class AlertAckHistoryLogTests: XCTestCase {
    func testAlertAckHistoryLog1() {
        let expected = AlertAckHistoryLog(
            // pumpTimeSec, sequenceNum, alertId
            pumpTimeSec: 580_260_938, sequenceNum: 469_779, alertId: 50
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "1b104a149622132b070032000000000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testAlertAckHistoryLog2() {
        let expected = AlertAckHistoryLog(
            // pumpTimeSec, sequenceNum, alertId
            pumpTimeSec: 580_095_340, sequenceNum: 462_908, alertId: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "1b106c8d93223c10070000000000000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
