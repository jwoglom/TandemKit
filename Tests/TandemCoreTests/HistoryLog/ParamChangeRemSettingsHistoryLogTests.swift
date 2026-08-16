@testable import TandemKit
import XCTest

// parse() skips raw bytes 12-13 between `status` and `lowBgThreshold`; across all six
// captured samples for this type those two bytes are 0x0000, so there is no evidence they
// carry meaningful unparsed data in this capture.
final class ParamChangeRemSettingsHistoryLogTests: XCTestCase {
    func testParamChangeRemSettingsHistoryLog1() {
        // pumpTimeSec, sequenceNum, modification, status, lowBgThreshold, highBgThreshold, siteChangeDays
        let expected = ParamChangeRemSettingsHistoryLog(
            pumpTimeSec: 580_601_544,
            sequenceNum: 483_934,
            modification: 2,
            status: 4,
            lowBgThreshold: 70,
            highBgThreshold: 200,
            siteChangeDays: 2
        ).withHeaderHighNibble(1)

        let parsedRes = HistoryLogMessageTester.testSingle(
            "6110c8469b225e620700020400004600c8000200000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
    }

    func testParamChangeRemSettingsHistoryLog2() {
        // pumpTimeSec, sequenceNum, modification, status, lowBgThreshold, highBgThreshold, siteChangeDays
        let expected = ParamChangeRemSettingsHistoryLog(
            pumpTimeSec: 579_744_851,
            sequenceNum: 448_177,
            modification: 2,
            status: 4,
            lowBgThreshold: 70,
            highBgThreshold: 200,
            siteChangeDays: 2
        ).withHeaderHighNibble(1)

        let parsedRes = HistoryLogMessageTester.testSingle(
            "611053348e22b1d60600020400004600c8000200000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
    }
}
