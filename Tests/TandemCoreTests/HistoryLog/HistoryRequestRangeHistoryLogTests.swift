@testable import TandemKit
import XCTest

final class HistoryRequestRangeHistoryLogTests: XCTestCase {
    func testHistoryRequestRangeMobi() {
        // Maintainer's Tandem Mobi; the 27 HistoryLogRequests in the two hours before had startLog 670898...671152.
        let expected = HistoryRequestRangeHistoryLog(
            pumpTimeSec: 590119266,
            sequenceNum: 671181,
            unknown10: 913,
            minStartLog: 670898,
            maxStartLog: 671152,
            unknown22: 0,
            unknown24: 26
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "eb1162812c23cd3d0a0091030000b23c0a00b03d0a0000001a00",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(670898, parsed.minStartLog)
        XCTAssertEqual(671152, parsed.maxStartLog)
        XCTAssertEqual(26, parsed.unknown24)
    }

    func testHistoryRequestRangeIssueExample() {
        let expected = HistoryRequestRangeHistoryLog(
            pumpTimeSec: 589528866,
            sequenceNum: 640817,
            unknown10: 533,
            minStartLog: 640509,
            maxStartLog: 640810,
            unknown22: 0,
            unknown24: 33
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "eb11227f232331c7090015020000fdc509002ac7090000002100",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
