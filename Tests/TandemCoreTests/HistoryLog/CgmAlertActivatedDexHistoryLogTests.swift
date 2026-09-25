@testable import TandemKit
import XCTest

final class CgmAlertActivatedDexHistoryLogTests: XCTestCase {
    func testCgmAlertActivatedDexHistoryLog1() {
        let expected = CgmAlertActivatedDexHistoryLog(
            pumpTimeSec: 580770552,
            sequenceNum: 490757,
            alertId: 2,
            sensorType: 3,
            faultLocatorData: 8468,
            param1: 208,
            param2: 200.0
        ).withHeaderHighNibble(1)

        let parsedRes = HistoryLogMessageTester.testSingle(
            "7111f8da9d22057d07000203000014210000d000000000004843",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
        XCTAssertEqual(parsedRes.sensorTypeEnum, .dexcomG7)
    }

    func testCgmAlertActivatedDexHistoryLog2() {
        let expected = CgmAlertActivatedDexHistoryLog(
            pumpTimeSec: 580720459,
            sequenceNum: 488615,
            alertId: 14,
            sensorType: 3,
            faultLocatorData: 8462,
            param1: 25,
            param2: 917.0
        ).withHeaderHighNibble(1)

        let parsedRes = HistoryLogMessageTester.testSingle(
            "71114b179d22a77407000e0300000e2100001900000000406544",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
        XCTAssertEqual(parsedRes.sensorTypeEnum, .dexcomG7)
    }
}
