@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `BolusRequestedMsg1HistoryLogTest`.
final class BolusRequestedMsg1HistoryLogTests: XCTestCase {
    func testBolusRequestedMsg1HistoryLog1() {
        let expected = BolusRequestedMsg1HistoryLog(
            pumpTimeSec: 445997729, sequenceNum: 181895, bolusId: 1036, bolusTypeId: 2,
            correctionBolusIncluded: true, carbAmount: 0, bg: 0, iob: 2.1372654, carbRatio: 0
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "4000a162951a87c602000c04020100000000f5c8084000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testBolusRequestedMsg1HistoryLog2() {
        let expected = BolusRequestedMsg1HistoryLog(
            pumpTimeSec: 446158654, sequenceNum: 186468, bolusId: 1057, bolusTypeId: 2,
            correctionBolusIncluded: true, carbAmount: 0, bg: 0, iob: 1.8658969, carbRatio: 0
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "40003ed7971a64d802002104020100000000b6d5ee3f00000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testBolusRequestedMsg1HistoryLog3() {
        let expected = BolusRequestedMsg1HistoryLog(
            pumpTimeSec: 446056900, sequenceNum: 183357, bolusId: 1040, bolusTypeId: 1,
            correctionBolusIncluded: false, carbAmount: 0, bg: 0, iob: 1.7629877, carbRatio: 6000
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "4000c449961a3dcc0200100401000000000095a9e13f70170000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.carbRatio, 6000)
        XCTAssertEqual(parsed.carbRatioGramsPerUnit, 6.0)
    }

    // Observed on a Tandem Mobi driven by Trio (Control-IQ off, no CGM paired), Sept 2026 BLE
    // capture. A remote (BLE) bolus without any calculator inputs: bolusTypeId=3 (REMOTE) with
    // correctionBolusIncluded/carbAmount/bg/iob/carbRatio all zero. Header high nibble is 1
    // (`40 10`), so the expected record is rebuilt with `.withHeaderHighNibble(1)`.
    func testBolusRequestedMsg1HistoryLogMobiRemoteBolus() {
        let expected = BolusRequestedMsg1HistoryLog(
            pumpTimeSec: 589526830, sequenceNum: 640746, bolusId: 2903, bolusTypeId: 3,
            correctionBolusIncluded: false, carbAmount: 0, bg: 0, iob: 0.0, carbRatio: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "40102e772323eac60900570b0300000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(BolusRequestedMsg1HistoryLog.BolusType.REMOTE, parsed.bolusType)
        XCTAssertEqual(2903, parsed.bolusId)
        XCTAssertFalse(parsed.correctionBolusIncluded)
        XCTAssertEqual(parsed.carbRatioGramsPerUnit, 0.0)
    }
}
