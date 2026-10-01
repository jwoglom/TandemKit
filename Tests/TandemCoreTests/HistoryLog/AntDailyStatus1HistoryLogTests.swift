@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `AntDailyStatus1HistoryLogTest`.
final class AntDailyStatus1HistoryLogTests: XCTestCase {
    func testAntDailyStatus1HistoryLogParse() {
        let expected = AntDailyStatus1HistoryLog(
            pumpTimeSec: 566_516_808,
            sequenceNum: 506_706,
            closedLoopPreferred: true,
            totalDailyInsulinUnits: 2,
            glycemicGoal: 2,
            priorTherapy: 2,
            sleepEatSegmentStartTime0: 304,
            sleepEatSegmentStartTime1: 305,
            sleepEatSegmentStartTime2: 306,
            sleepEatSegmentStartTime3: 307,
            sleepEatSegmentType0: 6,
            sleepEatSegmentType1: 6,
            sleepEatSegmentType2: 6,
            sleepEatSegmentType3: 6
        )

        let parsed = HistoryLogParser.parse(expected.cargo)
        guard let parsedRes = parsed as? AntDailyStatus1HistoryLog else {
            XCTFail("parsed \(type(of: parsed)), expected AntDailyStatus1HistoryLog")
            return
        }

        XCTAssertEqual(expected.pumpTimeSec, parsedRes.pumpTimeSec)
        XCTAssertEqual(expected.sequenceNum, parsedRes.sequenceNum)
        XCTAssertEqual(expected.closedLoopPreferred, parsedRes.closedLoopPreferred)
        XCTAssertEqual(expected.totalDailyInsulinUnits, parsedRes.totalDailyInsulinUnits)
        XCTAssertEqual(expected.glycemicGoal, parsedRes.glycemicGoal)
        XCTAssertEqual(expected.priorTherapy, parsedRes.priorTherapy)
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
