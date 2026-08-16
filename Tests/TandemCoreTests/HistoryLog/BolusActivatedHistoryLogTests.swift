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
}
