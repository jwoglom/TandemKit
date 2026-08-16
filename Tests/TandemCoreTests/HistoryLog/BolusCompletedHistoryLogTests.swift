@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `BolusCompletedHistoryLogTest`.
///
/// The Java test also asserts `getPumpTimeSecInstant()`; there is no equivalent accessor on the
/// Swift `HistoryLog` base class, so the instant is computed directly via
/// `Dates.fromJan12008EpochSecondsToDate` (the same helper other Swift history-log-adjacent code
/// already uses, e.g. `HistoryLogExport`).
final class BolusCompletedHistoryLogTests: XCTestCase {
    func testBolusCompletedHistoryLog() {
        let expected = BolusCompletedHistoryLog(
            pumpTimeSec: 446158750, sequenceNum: 186480, completionStatusId: 3, bolusId: 1057,
            iob: 3.652852, insulinDelivered: 1.7869551, insulinRequested: 1.7869551
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "14009ed7971a70d802000300210454c86940f2bae43ff2bae43f",
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(
            Dates.fromJan12008EpochSecondsToDate(TimeInterval(parsed.pumpTimeSec)),
            ISO8601DateFormatter().date(from: "2022-02-19T20:59:10Z")
        )
    }

    func testBolusCompletedHistoryLog_mismatchingFloats() {
        // BolusCompletedHistoryLog[bolusId=1047,completionStatus=3,insulinDelivered=0.89000005,insulinRequested=0.89,iob=1.0332867,cargo={20,0,0,91,-105,26,-7,-45,2,0,3,0,23,4,-67,66,-124,63,11,-41,99,63,10,-41,99,63},pumpTimeSec=446126848,sequenceNum=185337]
        let expected = BolusCompletedHistoryLog(
            pumpTimeSec: 446126848, sequenceNum: 185337, completionStatusId: 3, bolusId: 1047,
            iob: 1.0332867, insulinDelivered: 0.89000005, insulinRequested: 0.89
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "1400005b971af9d3020003001704bd42843f0bd7633f0ad7633f",
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(
            Dates.fromJan12008EpochSecondsToDate(TimeInterval(parsed.pumpTimeSec)),
            ISO8601DateFormatter().date(from: "2022-02-19T12:07:28Z")
        )
    }
}
