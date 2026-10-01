@testable import TandemKit
import XCTest

final class DateChangeHistoryLogTests: XCTestCase {
    // pumpX2 keeps this test @Ignore'd ("needs historyLog sample"), so the record may not be a pump capture.
    func testDateChangeHistoryLog() {
        let expected = DateChangeHistoryLog(
            pumpTimeSec: 456_260_319,
            sequenceNum: 2958,
            datePrior: 5185,
            dateAfter: 5280,
            rawRTCTime: 907_212_443
        )

        let parsed: DateChangeHistoryLog = HistoryLogMessageTester.testSingle(
            "0e00dffa311b8e0b000041140000a01400009bf6123600000000",
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(
            HistoryLogMessageTester.expectedDate(pumpWallClock: "2022-03-13T00:00:00Z"),
            Dates.fromJan12008EpochDaysToDate(TimeInterval(parsed.datePrior))
        )
        XCTAssertEqual(
            HistoryLogMessageTester.expectedDate(pumpWallClock: "2022-06-16T00:00:00Z"),
            Dates.fromJan12008EpochDaysToDate(TimeInterval(parsed.dateAfter))
        )
        XCTAssertEqual(
            HistoryLogMessageTester.expectedDate(pumpWallClock: "2022-06-16T18:58:39Z"),
            Dates.fromJan12008EpochSecondsToDate(TimeInterval(parsed.pumpTimeSec))
        )
    }
}
