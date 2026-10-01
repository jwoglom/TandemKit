@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `TempAdjustmentActivatedHistoryLogTest`.
final class TempAdjustmentActivatedHistoryLogTests: XCTestCase {
    func testTempAdjustmentActivatedHistoryLogParse() {
        let expected = TempAdjustmentActivatedHistoryLog(
            pumpTimeSec: 566_516_808,
            sequenceNum: 506_706,
            requestedPercent: 300,
            tempBasalPercent: 301,
            duration: 566517000,
            requestedAdjustmentType: 303,
            tempRateId: 304
        )

        let parsed = HistoryLogParser.parse(expected.cargo)
        guard let parsedRes = parsed as? TempAdjustmentActivatedHistoryLog else {
            XCTFail("parsed \(type(of: parsed)), expected TempAdjustmentActivatedHistoryLog")
            return
        }

        XCTAssertEqual(expected.pumpTimeSec, parsedRes.pumpTimeSec)
        XCTAssertEqual(expected.sequenceNum, parsedRes.sequenceNum)
        XCTAssertEqual(expected.requestedPercent, parsedRes.requestedPercent)
        XCTAssertEqual(expected.tempBasalPercent, parsedRes.tempBasalPercent)
        XCTAssertEqual(expected.duration, parsedRes.duration)
        XCTAssertEqual(expected.requestedAdjustmentType, parsedRes.requestedAdjustmentType)
        XCTAssertEqual(expected.tempRateId, parsedRes.tempRateId)
    }
}
