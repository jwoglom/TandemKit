@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `CgmJoinSessionFsl2HistoryLogTest`.
final class CgmJoinSessionFsl2HistoryLogTests: XCTestCase {
    func testCgmJoinSessionFsl2HistoryLogParse() {
        let expected = CgmJoinSessionFsl2HistoryLog(
            pumpTimeSec: 566_516_808,
            sequenceNum: 506_706,
            sessionStartTime: 566516800,
            sessionJoinTime: 566516900,
            sessionDuration: 5,
            sessionJoinReason: 6
        )

        let parsed = HistoryLogParser.parse(expected.cargo)
        guard let parsedRes = parsed as? CgmJoinSessionFsl2HistoryLog else {
            XCTFail("parsed \(type(of: parsed)), expected CgmJoinSessionFsl2HistoryLog")
            return
        }

        XCTAssertEqual(expected.pumpTimeSec, parsedRes.pumpTimeSec)
        XCTAssertEqual(expected.sequenceNum, parsedRes.sequenceNum)
        XCTAssertEqual(expected.sessionStartTime, parsedRes.sessionStartTime)
        XCTAssertEqual(expected.sessionJoinTime, parsedRes.sessionJoinTime)
        XCTAssertEqual(expected.sessionDuration, parsedRes.sessionDuration)
        XCTAssertEqual(expected.sessionJoinReason, parsedRes.sessionJoinReason)
    }
}
