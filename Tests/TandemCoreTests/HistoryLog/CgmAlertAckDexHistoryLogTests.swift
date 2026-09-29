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
        XCTAssertEqual(parsedRes.sensorTypeEnum, .dexcomG7)
        XCTAssertEqual(parsedRes.ackSourceEnum, .user)
    }

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
        XCTAssertEqual(parsedRes.sensorTypeEnum, .dexcomG7)
        XCTAssertEqual(parsedRes.ackSourceEnum, .software)
    }

    func testCgmAlertAckDexHistoryLogEnumMapping() {
        let g6 = CgmAlertAckDexHistoryLog(pumpTimeSec: 0, sequenceNum: 0, alertId: 2, sensorType: 1, ackSource: 0)
        XCTAssertEqual(g6.sensorTypeEnum, .dexcomG6)
        XCTAssertEqual(g6.ackSourceEnum, .user)
        let unknown = CgmAlertAckDexHistoryLog(pumpTimeSec: 0, sequenceNum: 0, alertId: 2, sensorType: 9, ackSource: 2)
        XCTAssertEqual(unknown.sensorTypeEnum, .unknown)
        XCTAssertNil(unknown.ackSourceEnum)
    }
}
