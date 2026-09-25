@testable import TandemKit
import XCTest

// Synthetic record: no FreeStyle Libre 2 capture exists. It uses the validated
// CgmAlertClearedDex (370) layout with sensorType 2 (FSL2) at byte 11.
final class CgmAlertClearedFsl2HistoryLogTests: XCTestCase {
    // The old uint32@10 read decoded this record as alertId 514 (2 + 2 << 8).
    func testCgmAlertClearedFsl2HistoryLogSynthetic() {
        let expected = CgmAlertClearedFsl2HistoryLog(
            pumpTimeSec: 600_000_300,
            sequenceNum: 1001,
            alertId: 2,
            sensorType: 2
        ).withHeaderHighNibble(1)

        let parsedRes = HistoryLogMessageTester.testSingle(
            "cd112c47c323e903000002020000000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
        XCTAssertEqual(parsedRes.alertId, 2)
        XCTAssertEqual(parsedRes.alert, .HIGH_CGM_ALERT)
        XCTAssertEqual(parsedRes.sensorType, 2)
        XCTAssertEqual(parsedRes.sensorTypeEnum, .fsl2)
    }
}
