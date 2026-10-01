@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `CgmStopSessionFsl3HistoryLogTest`.
final class CgmStopSessionFsl3HistoryLogTests: XCTestCase {
    func testCgmStopSessionFsl3HistoryLogParse() {
        let expected = CgmStopSessionFsl3HistoryLog(
            pumpTimeSec: 566_516_808,
            sequenceNum: 506_706,
            sessionStartTime: 566516800,
            sessionStopTime: 566516900,
            sessionDuration: 5,
            sessionStopReason: 6
        )

        let parsed = HistoryLogParser.parse(expected.cargo)
        guard let parsedRes = parsed as? CgmStopSessionFsl3HistoryLog else {
            XCTFail("parsed \(type(of: parsed)), expected CgmStopSessionFsl3HistoryLog")
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
