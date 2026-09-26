@testable import TandemKit
import XCTest

final class BatteryHourlyHistoryLogTests: XCTestCase {
    func testBatteryHourlyMobi90Percent() {
        // Maintainer's Tandem Mobi.
        let expected = BatteryHourlyHistoryLog(
            pumpTimeSec: 589528574,
            sequenceNum: 640810,
            currentBatteryIbc: 90,
            unknown12: 296,
            lipoMv: 4057,
            unknown16: 0,
            unknown18: 136,
            unknown20: 157,
            unknown22: 135,
            unknown24: 156
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "0f11fe7d23232ac709005a002801d90f000088009d0087009c00",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(90, parsed.currentBatteryIbc)
        XCTAssertEqual(4057, parsed.lipoMv)
    }

    func testBatteryHourlyMobiNegativeUnknown16() {
        // CurrentBatteryV2Response 33 seconds earlier: abc 92, ibc 95, unknown1 157, unknown2 144.
        let expected = BatteryHourlyHistoryLog(
            pumpTimeSec: 590115462,
            sequenceNum: 671001,
            currentBatteryIbc: 95,
            unknown12: 296,
            lipoMv: 4106,
            unknown16: -6,
            unknown18: 144,
            unknown20: 157,
            unknown22: 144,
            unknown24: 157
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "0f1186722c23193d0a005f0028010a10faff90009d0090009d00",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(-6, parsed.unknown16)
        XCTAssertEqual(92, Int((100.0 * Double(parsed.unknown18) / Double(parsed.unknown20)).rounded()))
    }

    func testBatteryHourlyMobiWhileCharging() {
        // CurrentBatteryV2Response 10 seconds later: chargingStatus 1, unknown4 207.
        let expected = BatteryHourlyHistoryLog(
            pumpTimeSec: 590518738,
            sequenceNum: 692795,
            currentBatteryIbc: 65,
            unknown12: 296,
            lipoMv: 4024,
            unknown16: 209,
            unknown18: 107,
            unknown20: 157,
            unknown22: 106,
            unknown24: 156
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "0f11d29932233b920a0041002801b80fd1006b009d006a009c00",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(209, parsed.unknown16)
    }

    func testBatteryHourlyMobiLowBatteryFlag() {
        let expected = BatteryHourlyHistoryLog(
            pumpTimeSec: 590882400,
            sequenceNum: 712415,
            currentBatteryIbc: 20,
            unknown12: 300,
            lipoMv: 3774,
            unknown16: 0,
            unknown18: 54,
            unknown20: 158,
            unknown22: 53,
            unknown24: 157
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "0f1160263823dfde0a0014002c01be0e000036009e0035009d00",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0x0004, parsed.unknown12 & 0x0004)
    }

    func testBatteryHourlyMobiFullAfterCharge() {
        let expected = BatteryHourlyHistoryLog(
            pumpTimeSec: 590615957,
            sequenceNum: 697799,
            currentBatteryIbc: 100,
            unknown12: 552,
            lipoMv: 4174,
            unknown16: 0,
            unknown18: 157,
            unknown20: 157,
            unknown22: 157,
            unknown24: 157
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "0f1195153423c7a50a00640028024e1000009d009d009d009d00",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(100, parsed.currentBatteryIbc)
    }
}
