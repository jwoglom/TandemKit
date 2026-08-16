@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `NewDayHistoryLogTest`.
final class NewDayHistoryLogTests: XCTestCase {
    func testNewDayHistoryLog1() {
        let expected = NewDayHistoryLog(
            // pumpTimeSec, sequenceNum, commandedBasalRate, featuresBitmask, featureBitmaskIndex
            pumpTimeSec: 580_521_600, sequenceNum: 480_602, commandedBasalRate: 3.4590001, featuresBitmask: 1_986_368_786, featureBitmaskIndex: 93
        ).withHeaderHighNibble(1)

        let parsedRes: NewDayHistoryLog = HistoryLogMessageTester.testSingle(
            "5a10800e9a225a55070042605d40129565765d00000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
    }

    func testNewDayHistoryLog2() {
        let expected = NewDayHistoryLog(
            // pumpTimeSec, sequenceNum, commandedBasalRate, featuresBitmask, featureBitmaskIndex
            pumpTimeSec: 580_694_400, sequenceNum: 487_757, commandedBasalRate: 0.0, featuresBitmask: 1_986_368_786, featureBitmaskIndex: 93
        ).withHeaderHighNibble(1)

        let parsedRes: NewDayHistoryLog = HistoryLogMessageTester.testSingle(
            "5a1080b19c224d71070000000000129565765d00000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
    }
}
