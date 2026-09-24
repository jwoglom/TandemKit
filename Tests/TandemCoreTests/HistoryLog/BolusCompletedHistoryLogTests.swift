@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `BolusCompletedHistoryLogTest`.
///
/// The Java test also asserts `getPumpTimeSecInstant()`; there is no equivalent accessor on the
/// Swift `HistoryLog` base class, so the instant is computed directly via
/// `Dates.fromJan12008EpochSecondsToDate` (the same helper other Swift history-log-adjacent code
/// already uses, e.g. `HistoryLogExport`), and the Java test's `Instant` literal is translated
/// from pump wall clock to an instant by `HistoryLogMessageTester.expectedDate(pumpWallClock:)`.
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
            HistoryLogMessageTester.expectedDate(pumpWallClock: "2022-02-19T20:59:10Z")
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
            HistoryLogMessageTester.expectedDate(pumpWallClock: "2022-02-19T12:07:28Z")
        )
    }

    // Observed on a Tandem Mobi driven by Trio (Control-IQ off, no CGM paired), Sept 2026 BLE capture.
    // Remote (BLE) bolus id 2903 of 0.15 u that ran to completion; the header high nibble is 1 on
    // this pump. Across the capture's 156 BolusCompleted records, bolusId at bytes 12-13 matched the
    // BolusActivated/BolusDelivery id for the same bolus in 156/156 and completionStatus at bytes
    // 10-11 was 3 (complete) in every record, confirming the Java field order over the byte-reversed
    // cloud-export mirror. insulinDelivered equalled insulinRequested bit-for-bit in all 156.
    func testBolusCompletedHistoryLog_mobiRemoteBolus() {
        let expected = BolusCompletedHistoryLog(
            pumpTimeSec: 589526849,
            sequenceNum: 640762,
            completionStatusId: 3,
            bolusId: 2903,
            iob: Float(bitPattern: 0x3fb21f75), // ~1.3916
            insulinDelivered: Float(bitPattern: 0x3e19999a), // 0.15
            insulinRequested: Float(bitPattern: 0x3e19999a) // 0.15
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "141041772323fac609000300570b751fb23f9a99193e9a99193e",
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.completionStatus, .complete)
        XCTAssertEqual(parsed.bolusId, 2903)
        XCTAssertEqual(parsed.insulinDelivered.bitPattern, parsed.insulinRequested.bitPattern)
        XCTAssertEqual(
            Dates.fromJan12008EpochSecondsToDate(TimeInterval(parsed.pumpTimeSec)),
            HistoryLogMessageTester.expectedDate(pumpWallClock: "2026-09-06T05:27:29Z")
        )
    }
}
