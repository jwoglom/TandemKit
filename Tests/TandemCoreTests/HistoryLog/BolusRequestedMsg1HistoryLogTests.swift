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
    }
}
