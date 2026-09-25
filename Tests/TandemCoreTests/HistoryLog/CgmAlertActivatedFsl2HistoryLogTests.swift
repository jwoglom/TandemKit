@testable import TandemKit
import XCTest

// Synthetic records: no FreeStyle Libre 2 capture exists. They use the validated
// CgmAlertActivatedDex (369) layout with sensorType 2 (FSL2) at byte 11.
final class CgmAlertActivatedFsl2HistoryLogTests: XCTestCase {
    func testCgmAlertActivatedFsl2HistoryLogSynthetic() {
        let expected = CgmAlertActivatedFsl2HistoryLog(
            pumpTimeSec: 600_000_000,
            sequenceNum: 1000,
            alertId: 2,
            sensorType: 2,
            faultLocatorData: 8468,
            param1: 250,
            param2: 200.0
        ).withHeaderHighNibble(1)

        let parsedRes = HistoryLogMessageTester.testSingle(
            "cc110046c323e80300000202000014210000fa00000000004843",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
        XCTAssertEqual(parsedRes.alertId, 2)
        XCTAssertEqual(parsedRes.alert, .HIGH_CGM_ALERT)
        XCTAssertEqual(parsedRes.sensorType, 2)
        XCTAssertEqual(parsedRes.sensorTypeEnum, .fsl2)
        XCTAssertEqual(parsedRes.faultLocatorData, 8468)
        XCTAssertEqual(parsedRes.param1, 250)
        XCTAssertEqual(parsedRes.param2, 200.0)
    }

    // The old uint32@10 read decoded this record as alertId 515 (3 + 2 << 8).
    func testCgmAlertActivatedFsl2HistoryLogSensorTypeDoesNotLeakIntoAlertId() {
        let expected = CgmAlertActivatedFsl2HistoryLog(
            pumpTimeSec: 600_000_000,
            sequenceNum: 1000,
            alertId: 3,
            sensorType: 2,
            faultLocatorData: 8466,
            param1: 70,
            param2: 80.0
        ).withHeaderHighNibble(1)

        let parsedRes = HistoryLogMessageTester.testSingle(
            "cc110046c323e80300000302000012210000460000000000a042",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
        XCTAssertEqual(parsedRes.alertId, 3)
        XCTAssertEqual(parsedRes.alert, .LOW_CGM_ALERT)
        XCTAssertEqual(parsedRes.sensorTypeEnum, .fsl2)
    }
}
