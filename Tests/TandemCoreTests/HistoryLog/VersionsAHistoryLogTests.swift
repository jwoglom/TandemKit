@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `VersionsAHistoryLogTest`.
final class VersionsAHistoryLogTests: XCTestCase {
    func testVersionsAHistoryLogParse() {
        let expected = VersionsAHistoryLog(
            // pumpTimeSec, sequenceNum, armPartNumber, armSwVersion, blePartNumber, bleSwVersion
            pumpTimeSec: 566_516_808, sequenceNum: 506_706, armPartNumber: 1_002_345, armSwVersion: 30_405_060, blePartNumber: 2_003_456, bleSwVersion: 40_506_070
        )

        let parsed = HistoryLogParser.parse(expected.cargo)
        XCTAssertTrue(parsed is VersionsAHistoryLog)

        let parsedRes = parsed as! VersionsAHistoryLog
        XCTAssertEqual(expected.pumpTimeSec, parsedRes.pumpTimeSec)
        XCTAssertEqual(expected.sequenceNum, parsedRes.sequenceNum)
        XCTAssertEqual(expected.armPartNumber, parsedRes.armPartNumber)
        XCTAssertEqual(expected.armSwVersion, parsedRes.armSwVersion)
        XCTAssertEqual(expected.blePartNumber, parsedRes.blePartNumber)
        XCTAssertEqual(expected.bleSwVersion, parsedRes.bleSwVersion)
    }
}
