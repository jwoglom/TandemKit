@testable import TandemKit
import XCTest

final class HistoryTimestampReconcilerTests: XCTestCase {
    func testAppliesClockChangeDeltasAfterSequence() {
        let reconciler = HistoryTimestampReconciler()
        reconciler.recordClockChange(at: 5, deltaSec: 3600)

        let baseDate = reconciler.utcDate(pumpTimeSec: 2000, sequenceNum: 6, timeZone: TimeZone(secondsFromGMT: 0)!)
        let expected = Date(timeIntervalSince1970: 2000 + 3600)

        XCTAssertEqual(baseDate, expected)
    }

    func testClockChangeDoesNotAffectPriorSequences() {
        let reconciler = HistoryTimestampReconciler()
        reconciler.recordClockChange(at: 10, deltaSec: -1800)

        let priorDate = reconciler.utcDate(pumpTimeSec: 5000, sequenceNum: 9, timeZone: TimeZone(secondsFromGMT: 0)!)
        let expected = Date(timeIntervalSince1970: 5000)

        XCTAssertEqual(priorDate, expected)
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

    func testBackwardClockChangeAdjustsTimestamps() {
        let reconciler = HistoryTimestampReconciler()
        reconciler.recordClockChange(at: 5, deltaSec: -3600)

        let adjusted = reconciler.utcDate(pumpTimeSec: 10000, sequenceNum: 6, timeZone: TimeZone(secondsFromGMT: 0)!)
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
