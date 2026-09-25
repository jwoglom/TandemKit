@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `BolexActivatedHistoryLogTest`.
final class BolexActivatedHistoryLogTests: XCTestCase {
    // Tandem Mobi, official Tandem app, March 2025 BLE capture. Extended bolus 248: 2 U, all of it
    // extended (BolusRequestedMsg2 options 5, standardPercent 0, 480 min), so no BolusActivated (55)
    // was written. Msg2 selectedIOB was 0, matching byte 12. Header high nibble is 1.
    func testBolexActivatedHistoryLogMobiExtendedBolus() {
        let expected = BolexActivatedHistoryLog(
            pumpTimeSec: 543715895, sequenceNum: 68927, bolusId: 248, selectedIob: 0, iob: 0.0, bolexSize: 2.0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "3b10377268203f0d0100f8000000000000000000004000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.bolusId, 248)
        XCTAssertEqual(parsed.selectedIob, 0)
        XCTAssertEqual(parsed.selectedIobType, .mudaliarIOB)
        XCTAssertEqual(parsed.iob, 0.0)
        XCTAssertEqual(parsed.bolexSize, 2.0)
    }

    // The captured record above has selectedIob 0; this SYNTHETIC record covers 1.
    func testBolexActivatedHistoryLogSyntheticRoundTrip() {
        let expected = BolexActivatedHistoryLog(
            pumpTimeSec: 1000, sequenceNum: 2000, bolusId: 0x1234, selectedIob: 1, iob: 1.5, bolexSize: 2.25
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "3b00e8030000d0070000341201000000c03f0000104000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(expected.cargo[12], 1)
        XCTAssertEqual(expected.cargo[13], 0)
        XCTAssertEqual(parsed.bolusId, 0x1234)
        XCTAssertEqual(parsed.selectedIob, 1)
        XCTAssertEqual(parsed.selectedIobType, .swanIOBMeal)
        XCTAssertEqual(parsed.iob, 1.5)
        XCTAssertEqual(parsed.bolexSize, 2.25)
    }

    func testBolexActivatedHistoryLogDefaultSelectedIobIsZero() {
        let log = BolexActivatedHistoryLog(pumpTimeSec: 1000, sequenceNum: 2000, bolusId: 0x1234, iob: 1.5, bolexSize: 2.25)

        MessageTester.assertHexEquals(log.cargo, Data(hexadecimalString: "3b00e8030000d0070000341200000000c03f0000104000000000")!)
        XCTAssertEqual(log.selectedIob, 0)
        XCTAssertEqual(log.selectedIobType, .mudaliarIOB)
    }
}
