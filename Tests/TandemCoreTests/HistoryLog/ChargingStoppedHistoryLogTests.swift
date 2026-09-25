@testable import TandemKit
import XCTest

final class ChargingStoppedHistoryLogTests: XCTestCase {
    func testChargingStoppedMobi() {
        // Maintainer's Tandem Mobi; CurrentBatteryV2Response in the same second: chargingStatus 1 -> 0, abc 59, ibc 50, unknown3 3967.
        let expected = ChargingStoppedHistoryLog(
            pumpTimeSec: 590518431,
            sequenceNum: 692768,
            currentBatteryAbc: 59,
            unknown12: 156,
            unknown14: 3058,
            currentBatteryIbc: 50,
            unknown18: 91,
            lipoMv: 3967,
            unknown22: 0,
            unknown24: 33
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "23109f98322320920a003b009c00f20b32005b007f0f00002100",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(59, parsed.currentBatteryAbc)
        XCTAssertEqual(50, parsed.currentBatteryIbc)
        XCTAssertEqual(3967, parsed.lipoMv)
    }

    func testChargingStoppedMobiEndOfSession() {
        let expected = ChargingStoppedHistoryLog(
            pumpTimeSec: 590519030,
            sequenceNum: 692802,
            currentBatteryAbc: 79,
            unknown12: 156,
            unknown14: 3079,
            currentBatteryIbc: 80,
            unknown18: 123,
            lipoMv: 4105,
            unknown22: 0,
            unknown24: 33
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "2310f69a322342920a004f009c00070c50007b00091000002100",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testChargingStoppedMobiIssueExampleFull() {
        let expected = ChargingStoppedHistoryLog(
            pumpTimeSec: 589554219,
            sequenceNum: 641961,
            currentBatteryAbc: 100,
            unknown12: 157,
            unknown14: 3083,
            currentBatteryIbc: 100,
            unknown18: 157,
            lipoMv: 4193,
            unknown22: 0,
            unknown24: 35
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "23102be22323a9cb090064009d000b0c64009d00611000002300",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testChargingStoppedTslimX2() {
        // Maintainer's t:slim X2, 3 seconds after a UsbDisconnected record.
        let expected = ChargingStoppedHistoryLog(
            pumpTimeSec: 534435776,
            sequenceNum: 1062525,
            currentBatteryAbc: 87,
            unknown12: 380,
            unknown14: 3071,
            currentBatteryIbc: 90,
            unknown18: 330,
            lipoMv: 4096,
            unknown22: 0,
            unknown24: 0
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "2300c0d7da1f7d36100057007c01ff0b5a004a01001000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
