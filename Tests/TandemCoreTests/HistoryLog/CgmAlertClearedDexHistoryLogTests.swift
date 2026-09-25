@testable import TandemKit
import XCTest

final class CgmAlertClearedDexHistoryLogTests: XCTestCase {
    func testCgmAlertClearedDexHistoryLog1() {
        let expected = CgmAlertClearedDexHistoryLog(
            pumpTimeSec: 580777763,
            sequenceNum: 491134,
            alertId: 2,
            sensorType: 3
        ).withHeaderHighNibble(1)

        let parsedRes = HistoryLogMessageTester.testSingle(
            "721123f79d227e7e070002030000000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
        XCTAssertEqual(parsedRes.sensorTypeEnum, .dexcomG7)
    }

    func testCgmAlertClearedDexHistoryLog2() {
        let expected = CgmAlertClearedDexHistoryLog(
            pumpTimeSec: 580720754,
            sequenceNum: 488623,
            alertId: 14,
            sensorType: 3
        ).withHeaderHighNibble(1)

        let parsedRes = HistoryLogMessageTester.testSingle(
            "721172189d22af7407000e030000000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
        XCTAssertEqual(parsedRes.sensorTypeEnum, .dexcomG7)
    }
}
