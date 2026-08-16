@testable import TandemKit
import XCTest

final class AlertClearedHistoryLogTests: XCTestCase {
    func testAlertClearedHistoryLog1() {
        let expected = AlertClearedHistoryLog(
            // pumpTimeSec, sequenceNum, alertId, faultLocatorData
            pumpTimeSec: 580_773_244, sequenceNum: 490_890, alertId: 50, faultLocatorData: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "1a107ce59d228a7d070032000000000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testAlertClearedHistoryLog2() {
        let expected = AlertClearedHistoryLog(
            // pumpTimeSec, sequenceNum, alertId, faultLocatorData
            pumpTimeSec: 580_474_756, sequenceNum: 478_427, alertId: 2, faultLocatorData: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "1a1084579922db4c070002000000000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
