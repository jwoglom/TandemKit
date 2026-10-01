@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `CgmJoinSessionFsl3HistoryLogTest`.
final class CgmJoinSessionFsl3HistoryLogTests: XCTestCase {
    func testCgmJoinSessionFsl3HistoryLogParse() {
        let expected = CgmJoinSessionFsl3HistoryLog(
            pumpTimeSec: 566_516_808,
            sequenceNum: 506_706,
            sessionStartTime: 566516800,
            sessionJoinTime: 566516900,
            sessionDuration: 5,
            sessionJoinReason: 6,
            sessionDurationSecs: 566517200
        )

        let parsed = HistoryLogParser.parse(expected.cargo)
        guard let parsedRes = parsed as? CgmJoinSessionFsl3HistoryLog else {
            XCTFail("parsed \(type(of: parsed)), expected CgmJoinSessionFsl3HistoryLog")
            return
        }

        XCTAssertEqual(expected.pumpTimeSec, parsedRes.pumpTimeSec)
        XCTAssertEqual(expected.sequenceNum, parsedRes.sequenceNum)
        XCTAssertEqual(expected.sessionStartTime, parsedRes.sessionStartTime)
        XCTAssertEqual(expected.sessionJoinTime, parsedRes.sessionJoinTime)
        XCTAssertEqual(expected.sessionDuration, parsedRes.sessionDuration)
        XCTAssertEqual(expected.sessionJoinReason, parsedRes.sessionJoinReason)
        XCTAssertEqual(expected.sessionDurationSecs, parsedRes.sessionDurationSecs)
    }
}
