@testable import TandemKit
import XCTest

final class ChargingStartedHistoryLogTests: XCTestCase {
    func testChargingStartedMobi() {
        // Maintainer's Tandem Mobi; CurrentBatteryV2Response 1 second later: chargingStatus 0 -> 1, abc 32, ibc 20, unknown3 3762.
        let expected = ChargingStartedHistoryLog(
            pumpTimeSec: 590517712,
            sequenceNum: 692754,
            currentBatteryAbc: 32,
            unknown12: 155,
            unknown14: 3027,
            currentBatteryIbc: 20,
            unknown18: 49,
            lipoMv: 3762,
            unknown22: 0,
            unknown24: 29
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "2210d095322312920a0020009b00d30b14003100b20e00001d00",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(32, parsed.currentBatteryAbc)
        XCTAssertEqual(20, parsed.currentBatteryIbc)
        XCTAssertEqual(3762, parsed.lipoMv)
    }

    func testChargingStartedMobiIssueExample() {
        let expected = ChargingStartedHistoryLog(
            pumpTimeSec: 589553337,
            sequenceNum: 641942,
            currentBatteryAbc: 79,
            unknown12: 157,
            unknown14: 3031,
            currentBatteryIbc: 80,
            unknown18: 124,
            lipoMv: 3998,
            unknown22: 0,
            unknown24: 29
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "2210b9de232396cb09004f009d00d70b50007c009e0f00001d00",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testChargingStartedTslimX2() {
        // Maintainer's t:slim X2, 4 seconds after a UsbConnected record.
        let expected = ChargingStartedHistoryLog(
            pumpTimeSec: 534434756,
            sequenceNum: 1062478,
            currentBatteryAbc: 70,
            unknown12: 380,
            unknown14: 3047,
            currentBatteryIbc: 65,
            unknown18: 263,
            lipoMv: 3924,
            unknown22: 0,
            unknown24: 0
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "2200c4d3da1f4e36100046007c01e70b41000701540f00000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(Double(parsed.currentBatteryAbc), 100.0 * Double(parsed.unknown18) / Double(parsed.unknown12), accuracy: 1.0)
    }
}
