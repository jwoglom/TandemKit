@testable import TandemKit
import XCTest

final class CgmAlertAckDexHistoryLogTests: XCTestCase {
    func testCgmAlertAckDexHistoryLog1() {
        let expected = CgmAlertAckDexHistoryLog(
            pumpTimeSec: 580750504,
            sequenceNum: 489859,
            alertId: 2,
            sensorType: 3,
            ackSource: 0
        ).withHeaderHighNibble(1)

        let parsedRes = HistoryLogMessageTester.testSingle(
            "7311a88c9d228379070002030000000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
    }

    // this sample's ackSource=1 (raw byte 14 = 0x01) reflects the alert being acknowledged
    // from a source other than the default
    func testCgmAlertAckDexHistoryLog2() {
        let expected = CgmAlertAckDexHistoryLog(
            pumpTimeSec: 579789268,
            sequenceNum: 449784,
            alertId: 32,
            sensorType: 3,
            ackSource: 1
        ).withHeaderHighNibble(1)

        let parsedRes = HistoryLogMessageTester.testSingle(
            "7311d4e18e22f8dc060020030000010000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
    }
}
