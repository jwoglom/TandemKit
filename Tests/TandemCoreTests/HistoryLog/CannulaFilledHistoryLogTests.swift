@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `CannulaFilledHistoryLogTest`.
final class CannulaFilledHistoryLogTests: XCTestCase {
    func testCannulaFilledHistoryLog1() {
        let expected = CannulaFilledHistoryLog(
            // pumpTimeSec, sequenceNum, primeSize, completionStatus
            pumpTimeSec: 580_601_541, sequenceNum: 483_933, primeSize: 0.3, completionStatus: 3
        ).withHeaderHighNibble(1)

        let parsedRes: CannulaFilledHistoryLog = HistoryLogMessageTester.testSingle(
            "3d10c5469b225d6207009a99993e030000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
        XCTAssertEqual(.defaultTubed, parsedRes.infusionSetType)
    }

    func testCannulaFilledHistoryLog2() {
        let expected = CannulaFilledHistoryLog(
            // pumpTimeSec, sequenceNum, primeSize, completionStatus
            pumpTimeSec: 579_744_849, sequenceNum: 448_176, primeSize: 0.3, completionStatus: 3
        ).withHeaderHighNibble(1)

        let parsedRes: CannulaFilledHistoryLog = HistoryLogMessageTester.testSingle(
            "3d1051348e22b0d606009a99993e030000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
    }
}
