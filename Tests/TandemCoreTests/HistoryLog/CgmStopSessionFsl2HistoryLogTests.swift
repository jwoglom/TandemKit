@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `CgmStopSessionFsl2HistoryLogTest`.
final class CgmStopSessionFsl2HistoryLogTests: XCTestCase {
    func testCgmStopSessionFsl2HistoryLogParse() {
        let expected = CgmStopSessionFsl2HistoryLog(
            pumpTimeSec: 566_516_808,
            sequenceNum: 506_706,
            sessionStartTime: 566516800,
            sessionStopTime: 566516900,
            sessionDuration: 5,
            sessionStopReason: 6
        )

        let parsed = HistoryLogParser.parse(expected.cargo)
        guard let parsedRes = parsed as? CgmStopSessionFsl2HistoryLog else {
            XCTFail("parsed \(type(of: parsed)), expected CgmStopSessionFsl2HistoryLog")
            return
        }

        XCTAssertEqual(expected.pumpTimeSec, parsedRes.pumpTimeSec)
        XCTAssertEqual(expected.sequenceNum, parsedRes.sequenceNum)
        XCTAssertEqual(expected.sessionStartTime, parsedRes.sessionStartTime)
        XCTAssertEqual(expected.sessionStopTime, parsedRes.sessionStopTime)
        XCTAssertEqual(expected.sessionDuration, parsedRes.sessionDuration)
        XCTAssertEqual(expected.sessionStopReason, parsedRes.sessionStopReason)
    }
}
