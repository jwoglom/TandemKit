@testable import TandemKit
import XCTest

/// Ported from pumpX2's `TempRateCompletedHistoryLogTest`.
final class TempRateCompletedHistoryLogTests: XCTestCase {
    func testTempRateCompletedHistoryLog1() {
        let expected = TempRateCompletedHistoryLog(
            pumpTimeSec: 579784686,
            sequenceNum: 449606,
            tempRateId: 21,
            timeLeft: 0
        )

        _ = HistoryLogMessageTester.testSingle(
            "0f10eecf8e2246dc060003001500000000000000000000000000",
            expected
        )
        // no cargo round-trip: bytes 10-11 carry unparsed data (0x0003 LE) that buildCargo does
        // not reproduce
    }

    func testBuiltCargoParsesBackToItsFields() {
        let built = TempRateCompletedHistoryLog(pumpTimeSec: 579784686, sequenceNum: 449606, tempRateId: 21, timeLeft: 1200)

        let parsed = TempRateCompletedHistoryLog(cargo: built.cargo)

        XCTAssertEqual(parsed.tempRateId, 21)
        XCTAssertEqual(parsed.timeLeft, 1200)
        XCTAssertEqual(parsed.sequenceNum, 449606)
    }
}
