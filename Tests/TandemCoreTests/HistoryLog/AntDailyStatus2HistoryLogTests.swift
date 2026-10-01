@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `AntDailyStatus2HistoryLogTest`.
final class AntDailyStatus2HistoryLogTests: XCTestCase {
    func testAntDailyStatus2HistoryLogParse() {
        let expected = AntDailyStatus2HistoryLog(
            pumpTimeSec: 566_516_808,
            sequenceNum: 506_706,
            pumpControlState: 1,
            sensorType: 2
        )

        let parsed = HistoryLogParser.parse(expected.cargo)
        guard let parsedRes = parsed as? AntDailyStatus2HistoryLog else {
            XCTFail("parsed \(type(of: parsed)), expected AntDailyStatus2HistoryLog")
            return
        }

        XCTAssertEqual(expected.pumpTimeSec, parsedRes.pumpTimeSec)
        XCTAssertEqual(expected.sequenceNum, parsedRes.sequenceNum)
        XCTAssertEqual(expected.pumpControlState, parsedRes.pumpControlState)
        XCTAssertEqual(expected.sensorType, parsedRes.sensorType)
    }
}
