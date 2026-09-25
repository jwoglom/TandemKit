@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `BolusActivatedHistoryLogTest`.
final class BolusActivatedHistoryLogTests: XCTestCase {
    func testBolusActivatedHistoryLog1() {
        let expected = BolusActivatedHistoryLog(
            pumpTimeSec: 446033777, sequenceNum: 182751, bolusId: 1037, selectedIob: 1, iob: 0.0, bolusSize: 1.1
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "370071ef951adfc902000d04010000000000cdcc8c3f00000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.selectedIob, 1)
        XCTAssertEqual(parsed.selectedIobType, .swanIOBMeal)
    }

    func testBolusActivatedHistoryLog2() {
        let expected = BolusActivatedHistoryLog(
            pumpTimeSec: 446141315, sequenceNum: 185926, bolusId: 1053, selectedIob: 1, iob: 2.0116007, bolusSize: 0.5
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "37008393971a46d602001d04010011be00400000003f00000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    // Observed on a Tandem Mobi driven by Trio (Control-IQ off, no CGM paired), Sept 2026 BLE capture.
    // Remote (BLE) bolus id 2903, 0.15 U. Across 156 such records bolusId@10 matched the paired
    // BolusRequestedMsg1/2/3, BolusDelivery and BolusCompleted ids in 156/156; byte 11 (0x0B) is the
    // high byte of that id, not a selectedIob field; byte 12 (selectedIob) was 0 in all 156, equal to
    // selectedIOB@24 of every paired BolusRequestedMsg2. Header high nibble is 1 on this capture.
    func testBolusActivatedHistoryLogMobiRemoteBolus() {
        let expected = BolusActivatedHistoryLog(
            pumpTimeSec: 589526845,
            sequenceNum: 640754,
            bolusId: 2903,
            selectedIob: 0,
            iob: Float(bitPattern: 0x3f9eec42), // ~1.2416
            bolusSize: Float(bitPattern: 0x3e19999a) // 0.15
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "37103d772323f2c60900570b000042ec9e3f9a99193e00000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.bolusId, 2903)
        XCTAssertEqual(parsed.selectedIob, 0)
        XCTAssertEqual(parsed.selectedIobType, .mudaliarIOB)
        XCTAssertEqual(parsed.iob.bitPattern, 0x3f9eec42)
        XCTAssertEqual(parsed.bolusSize.bitPattern, 0x3e19999a)
    }
}
