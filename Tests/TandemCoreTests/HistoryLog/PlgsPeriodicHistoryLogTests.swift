@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `PlgsPeriodicHistoryLogTest`.
final class PlgsPeriodicHistoryLogTests: XCTestCase {
    func testPlgsPeriodicHistoryLogParse() {
        let expected = PlgsPeriodicHistoryLog(
            pumpTimeSec: 566_516_808,
            sequenceNum: 506_706,
            timestamp: 566516800,
            fmr: 301,
            pgv: 302,
            fmrStatus: 4,
            pgvValid: true,
            ruleState: 6,
            hoMinState: 3,
            status: 566517500
        )

        let parsed = HistoryLogParser.parse(expected.cargo)
        guard let parsedRes = parsed as? PlgsPeriodicHistoryLog else {
            XCTFail("parsed \(type(of: parsed)), expected PlgsPeriodicHistoryLog")
            return
        }

        XCTAssertEqual(expected.pumpTimeSec, parsedRes.pumpTimeSec)
        XCTAssertEqual(expected.sequenceNum, parsedRes.sequenceNum)
        XCTAssertEqual(expected.timestamp, parsedRes.timestamp)
        XCTAssertEqual(expected.fmr, parsedRes.fmr)
        XCTAssertEqual(expected.pgv, parsedRes.pgv)
        XCTAssertEqual(expected.fmrStatus, parsedRes.fmrStatus)
        XCTAssertEqual(expected.pgvValid, parsedRes.pgvValid)
        XCTAssertEqual(expected.ruleState, parsedRes.ruleState)
        XCTAssertEqual(expected.hoMinState, parsedRes.hoMinState)
        XCTAssertEqual(expected.status, parsedRes.status)
    }
}
