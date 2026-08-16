@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `CarbEnteredHistoryLogTest`.
///
/// The Java test uses `testSingleIgnoringBaseFields` with a carbs-only constructor since it
/// doesn't care about pumpTimeSec/sequenceNum. There is no `testSingleIgnoringBaseFields`
/// equivalent on the Swift `HistoryLogMessageTester`, so this port decodes the real pumpTimeSec
/// and sequenceNum from each fixture and asserts the full record via the ordinary `testSingle`.
final class CarbEnteredHistoryLogTests: XCTestCase {
    func testCarbEnteredHistoryLog1() {
        let expected = CarbEnteredHistoryLog(pumpTimeSec: 446145742, sequenceNum: 186065, carbs: 45.0)

        let parsed = HistoryLogMessageTester.testSingle(
            "3000cea4971ad1d6020000003442000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testCarbEnteredHistoryLog2() {
        let expected = CarbEnteredHistoryLog(pumpTimeSec: 446227142, sequenceNum: 188375, carbs: 60.0)

        let parsed = HistoryLogMessageTester.testSingle(
            "3000c6e2981ad7df020000007042000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
