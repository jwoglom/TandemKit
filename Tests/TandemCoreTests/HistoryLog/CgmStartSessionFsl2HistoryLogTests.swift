@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `CgmStartSessionFsl2HistoryLogTest`.
final class CgmStartSessionFsl2HistoryLogTests: XCTestCase {
    func testCgmStartSessionFsl2HistoryLogParse() {
        let expected = CgmStartSessionFsl2HistoryLog(
            pumpTimeSec: 566_516_808,
            sequenceNum: 506_706,
            sessionStartTime: 566516800,
            sessionDuration: 4
        )

        let parsed = HistoryLogParser.parse(expected.cargo)
        guard let parsedRes = parsed as? CgmStartSessionFsl2HistoryLog else {
            XCTFail("parsed \(type(of: parsed)), expected CgmStartSessionFsl2HistoryLog")
            return
        }

        XCTAssertEqual(expected.pumpTimeSec, parsedRes.pumpTimeSec)
        XCTAssertEqual(expected.sequenceNum, parsedRes.sequenceNum)
        XCTAssertEqual(expected.sessionStartTime, parsedRes.sessionStartTime)
        XCTAssertEqual(expected.sessionDuration, parsedRes.sessionDuration)
    }
}
