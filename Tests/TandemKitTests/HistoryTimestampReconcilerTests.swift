@testable import TandemKit
import XCTest

final class HistoryTimestampReconcilerTests: XCTestCase {
    func testAppliesClockChangeDeltasToEarlierSequences() {
        // Records BEFORE a clock change were stamped under the old clock; applying the delta
        // brings them onto the current clock.
        let reconciler = HistoryTimestampReconciler()
        reconciler.recordClockChange(at: 5, deltaSec: 3600)

        let earlierDate = reconciler.utcDate(pumpTimeSec: 2000, sequenceNum: 4, timeZone: TimeZone(secondsFromGMT: 0)!)
        let expected = Date(timeIntervalSince1970: 2000 + 3600)

        XCTAssertEqual(earlierDate, expected)
    }

    func testClockChangeDoesNotAffectLaterSequences() {
        // Records AFTER a clock change are already on the current clock; no adjustment.
        let reconciler = HistoryTimestampReconciler()
        reconciler.recordClockChange(at: 10, deltaSec: -1800)

        let laterDate = reconciler.utcDate(pumpTimeSec: 5000, sequenceNum: 11, timeZone: TimeZone(secondsFromGMT: 0)!)
        let expected = Date(timeIntervalSince1970: 5000)

        XCTAssertEqual(laterDate, expected)
    }

    func testUtcConversionRespectsTimeZoneOffset() {
        let reconciler = HistoryTimestampReconciler()
        let timeZone = TimeZone(secondsFromGMT: 3600)!

        let date = reconciler.utcDate(pumpTimeSec: 7200, sequenceNum: 1, timeZone: timeZone)
        let expected = Date(timeIntervalSince1970: 3600)

        XCTAssertEqual(date, expected)
    }

    func testDetectsLargeForwardJumps() {
        let reconciler = HistoryTimestampReconciler()
        XCTAssertTrue(reconciler.isValidTimestamp(1000, sequenceNum: 1))
        XCTAssertFalse(reconciler.isValidTimestamp(90000, sequenceNum: 2))
    }

    func testBackwardClockChangeAdjustsEarlierTimestamps() {
        let reconciler = HistoryTimestampReconciler()
        reconciler.recordClockChange(at: 5, deltaSec: -3600)

        let adjusted = reconciler.utcDate(pumpTimeSec: 10000, sequenceNum: 4, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(adjusted, Date(timeIntervalSince1970: 6400))
    }

    func testDstTransitionUsesContemporaryOffset() throws {
        let reconciler = HistoryTimestampReconciler()
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let utcBefore = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 3, day: 10, hour: 9, minute: 30)))
        let utcAfter = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 3, day: 10, hour: 10, minute: 30)))

        let pumpBefore = UInt32(utcBefore.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: utcBefore)))
        let pumpAfter = UInt32(utcAfter.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: utcAfter)))

        let reconciledBefore = reconciler.utcDate(pumpTimeSec: pumpBefore, sequenceNum: 1, timeZone: timeZone)
        let reconciledAfter = reconciler.utcDate(pumpTimeSec: pumpAfter, sequenceNum: 2, timeZone: timeZone)

        XCTAssertEqual(reconciledBefore, utcBefore)
        XCTAssertEqual(reconciledAfter, utcAfter)
    }
}
