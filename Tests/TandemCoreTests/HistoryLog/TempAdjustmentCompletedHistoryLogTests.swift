@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `TempAdjustmentCompletedHistoryLogTest`.
final class TempAdjustmentCompletedHistoryLogTests: XCTestCase {
    func testTempAdjustmentCompletedHistoryLogParse() {
        let expected = TempAdjustmentCompletedHistoryLog(
            pumpTimeSec: 566_516_808,
            sequenceNum: 506_706,
            stopReason: 300,
            tempRateId: 301,
            timeLeft: 566517000
        )

        let parsed = HistoryLogParser.parse(expected.cargo)
        guard let parsedRes = parsed as? TempAdjustmentCompletedHistoryLog else {
            XCTFail("parsed \(type(of: parsed)), expected TempAdjustmentCompletedHistoryLog")
            return
        }

        XCTAssertEqual(expected.pumpTimeSec, parsedRes.pumpTimeSec)
        XCTAssertEqual(expected.sequenceNum, parsedRes.sequenceNum)
        XCTAssertEqual(expected.stopReason, parsedRes.stopReason)
        XCTAssertEqual(expected.tempRateId, parsedRes.tempRateId)
        XCTAssertEqual(expected.timeLeft, parsedRes.timeLeft)
    }
}
