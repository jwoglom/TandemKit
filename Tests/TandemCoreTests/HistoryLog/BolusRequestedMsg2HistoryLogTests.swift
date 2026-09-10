@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `BolusRequestedMsg2HistoryLogTest`.
///
/// The Java `_declinedCorrection` case uses `testSingleIgnoringBaseFields` with a bolusId-only
/// constructor, since it doesn't care about pumpTimeSec/sequenceNum. There is no
/// `testSingleIgnoringBaseFields` equivalent on the Swift `HistoryLogMessageTester`, so this port
/// decodes the real pumpTimeSec (446231753) and sequenceNum (188529) from the fixture — matching
/// the values already visible in the Java test's own comment — and asserts the full record via
/// the ordinary `testSingle`.
final class BolusRequestedMsg2HistoryLogTests: XCTestCase {
    func testBolusRequestedMsg2HistoryLog1() {
        let expected = BolusRequestedMsg2HistoryLog(
            pumpTimeSec: 445961478, sequenceNum: 180876, bolusId: 1028, options: 0, standardPercent: 100,
            duration: 0, spare1: 0, isf: 30, targetBG: 110, userOverride: true, declinedCorrection: false,
            selectedIOB: 1, spare2: 0
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "410006d5941a8cc2020004040064000000001e006e0001000100",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testBolusRequestedMsg2HistoryLog2() {
        let expected = BolusRequestedMsg2HistoryLog(
            pumpTimeSec: 445948266, sequenceNum: 180529, bolusId: 1026, options: 0, standardPercent: 100,
            duration: 0, spare1: 0, isf: 30, targetBG: 110, userOverride: false, declinedCorrection: false,
            selectedIOB: 1, spare2: 0
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "41006aa1941a31c1020002040064000000001e006e0000000100",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testBolusRequestedMsg2HistoryLog_declinedCorrection() {
        // 4100c9f4981a71e002002e040064000000001e006e0000010100	BolusRequestedMsg2HistoryLog[bolusId=1070,declinedCorrection=true,duration=0,isf=30,options=0,selectedIOB=1,spare1=0,spare2=0,standardPercent=100,targetBG=110,userOverride=false,cargo={65,0,-55,-12,-104,26,113,-32,2,0,46,4,0,100,0,0,0,0,30,0,110,0,0,1,1,0},pumpTimeSec=446231753,sequenceNum=188529]
        let expected = BolusRequestedMsg2HistoryLog(
            pumpTimeSec: 446231753, sequenceNum: 188529, bolusId: 1070, options: 0, standardPercent: 100,
            duration: 0, spare1: 0, isf: 30, targetBG: 110, userOverride: false, declinedCorrection: true,
            selectedIOB: 1, spare2: 0
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "4100c9f4981a71e002002e040064000000001e006e0000010100",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    /// Observed on a Tandem Mobi driven by Trio (Control-IQ off, no CGM paired), Sept 2026 BLE
    /// capture. A bolus initiated over BLE via `InitiateBolusRequest` (bolusSource 8 in the paired
    /// BolusDeliveryHistoryLog): options=4 (`bleStandard`) with standardPercent=100, duration=0,
    /// isf/targetBG=0, userOverride=true. 156/156 BLE-initiated boluses in the capture matched.
    /// The header high nibble is 1 in this capture, as in the BasalDelivery fixtures.
    /// See pumpX2 issue #51.
    func testBolusRequestedMsg2HistoryLog_bleStandardMobi() {
        // 41102e772323ebc60900570b0464000000000000000001000000
        let expected = BolusRequestedMsg2HistoryLog(
            pumpTimeSec: 589526830, sequenceNum: 640747, bolusId: 2903, options: 4, standardPercent: 100,
            duration: 0, spare1: 0, isf: 0, targetBG: 0, userOverride: true, declinedCorrection: false,
            selectedIOB: 0, spare2: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "41102e772323ebc60900570b0464000000000000000001000000",
            expected
        )
        XCTAssertEqual(parsed.bolusOption, .bleStandard)
        XCTAssertEqual(parsed.standardPercent, 100)
        XCTAssertTrue(parsed.userOverride)
        XCTAssertFalse(parsed.declinedCorrection)
        XCTAssertEqual(parsed.selectedIOB, 0)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
