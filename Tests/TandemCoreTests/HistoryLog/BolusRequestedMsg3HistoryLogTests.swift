@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `BolusRequestedMsg3HistoryLogTest`.
final class BolusRequestedMsg3HistoryLogTests: XCTestCase {
    func testBolusRequestedMsg3HistoryLog() {
        let expected = BolusRequestedMsg3HistoryLog(
            pumpTimeSec: 445992481, sequenceNum: 181642, bolusId: 1032, spare: 0,
            foodBolusSize: 3.33, correctionBolusSize: 0.0, totalBolusSize: 3.33
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "4200214e951a8ac5020008040000b81e554000000000b81e5540",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testBolusRequestedMsg3HistoryLog2() {
        // BolusRequestedMsg3HistoryLog[bolusId=1066,correctionBolusSize=0.27,foodBolusSize=6.67,spare=0,totalBolusSize=6.94,cargo={66,0,77,-82,-104,26,48,-34,2,0,42,4,0,0,-92,112,-43,64,113,61,-118,62,123,20,-34,64},pumpTimeSec=446213709,sequenceNum=187952]
        let expected = BolusRequestedMsg3HistoryLog(
            pumpTimeSec: 446213709, sequenceNum: 187952, bolusId: 1066, spare: 0,
            foodBolusSize: 6.67, correctionBolusSize: 0.27, totalBolusSize: 6.94
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "42004dae981a30de02002a040000a470d540713d8a3e7b14de40",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    // Observed on a Tandem Mobi driven by Trio (Control-IQ off, no CGM paired), Sept 2026 BLE capture.
    // Third record of a remote (BLE) bolus request, id 2903, for 0.15 U with no correction.
    // Header high nibble is 1 on this pump; the float fields are built from their exact bit
    // patterns so the round trip below is byte-exact.
    func testBolusRequestedMsg3HistoryLogMobiRemoteBolus() {
        let food = Float(bitPattern: 0x3e19999a) // 0.15
        let expected = BolusRequestedMsg3HistoryLog(
            pumpTimeSec: 589526830, sequenceNum: 640748, bolusId: 2903, spare: 0,
            foodBolusSize: food, correctionBolusSize: 0.0, totalBolusSize: food
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "42102e772323ecc60900570b00009a99193e000000009a99193e",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)

        XCTAssertEqual(parsed.bolusId, 2903)
        XCTAssertEqual(parsed.spare, 0)
        XCTAssertEqual(parsed.foodBolusSize.bitPattern, 0x3e19999a)
        XCTAssertEqual(parsed.correctionBolusSize, 0.0)
        XCTAssertEqual(parsed.totalBolusSize, parsed.foodBolusSize)
    }
}
