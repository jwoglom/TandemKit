@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `AntSleepEatSchedSettingChangeHistoryLogTest`.
final class AntSleepEatSchedSettingChangeHistoryLogTests: XCTestCase {
    func testAntSleepEatSchedSettingChangeHistoryLogParse() {
        let expected = AntSleepEatSchedSettingChangeHistoryLog(
            pumpTimeSec: 566_516_808,
            sequenceNum: 506_706,
            sleepEatSegmentStartTime0: 300,
            sleepEatSegmentStartTime1: 301,
            sleepEatSegmentStartTime2: 302,
            sleepEatSegmentStartTime3: 303,
            sleepEatSegmentType0: 5,
            sleepEatSegmentType1: 6,
            sleepEatSegmentType2: 7,
            sleepEatSegmentType3: 7
        )

        let parsed = HistoryLogParser.parse(expected.cargo)
        guard let parsedRes = parsed as? AntSleepEatSchedSettingChangeHistoryLog else {
            XCTFail("parsed \(type(of: parsed)), expected AntSleepEatSchedSettingChangeHistoryLog")
            return
        }

        XCTAssertEqual(expected.pumpTimeSec, parsedRes.pumpTimeSec)
        XCTAssertEqual(expected.sequenceNum, parsedRes.sequenceNum)
        XCTAssertEqual(expected.sleepEatSegmentStartTime0, parsedRes.sleepEatSegmentStartTime0)
        XCTAssertEqual(expected.sleepEatSegmentStartTime1, parsedRes.sleepEatSegmentStartTime1)
        XCTAssertEqual(expected.sleepEatSegmentStartTime2, parsedRes.sleepEatSegmentStartTime2)
        XCTAssertEqual(expected.sleepEatSegmentStartTime3, parsedRes.sleepEatSegmentStartTime3)
        XCTAssertEqual(expected.sleepEatSegmentType0, parsedRes.sleepEatSegmentType0)
        XCTAssertEqual(expected.sleepEatSegmentType1, parsedRes.sleepEatSegmentType1)
        XCTAssertEqual(expected.sleepEatSegmentType2, parsedRes.sleepEatSegmentType2)
        XCTAssertEqual(expected.sleepEatSegmentType3, parsedRes.sleepEatSegmentType3)
    }
}
