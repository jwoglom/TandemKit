@testable import TandemKit
import XCTest

/// Expectations are computed through `Dates.fromJan12008EpochSecondsToDate` — the same
/// conversion the reconciler delegates to — so these tests pin the reconciler's own job (delta
/// bookkeeping by sequence number) without re-testing the epoch/offset conversion or depending
/// on the machine's time zone.
final class HistoryTimestampReconcilerTests: XCTestCase {
    private func pumpDate(_ pumpTimeSec: Int) -> Date {
        Dates.fromJan12008EpochSecondsToDate(TimeInterval(pumpTimeSec))
    }

    func testAppliesDeltaToRecordsBeforeTheChange() {
        // Records BEFORE a clock change were stamped under the old clock; applying the delta
        // brings them onto the current clock.
        let reconciler = HistoryTimestampReconciler()
        reconciler.recordClockChange(at: 5, deltaSec: 3600)

        XCTAssertEqual(reconciler.utcDate(pumpTimeSec: 2000, sequenceNum: 4), pumpDate(2000 + 3600))
    }

    func testDoesNotAdjustRecordsAtOrAfterTheChange() {
        // The change record itself, and everything after it, is already stamped under the new
        // clock.
        let reconciler = HistoryTimestampReconciler()
        reconciler.recordClockChange(at: 10, deltaSec: -1800)

        XCTAssertEqual(reconciler.utcDate(pumpTimeSec: 5000, sequenceNum: 10), pumpDate(5000))
        XCTAssertEqual(reconciler.utcDate(pumpTimeSec: 5000, sequenceNum: 11), pumpDate(5000))
    }

    func testAppliesBackwardDelta() {
        let reconciler = HistoryTimestampReconciler()
        reconciler.recordClockChange(at: 5, deltaSec: -3600)

        XCTAssertEqual(reconciler.utcDate(pumpTimeSec: 10000, sequenceNum: 4), pumpDate(10000 - 3600))
    }

    func testAccumulatesOnlyChangesAfterTheRecord() {
        // A record is adjusted by every change that happened after it was written — and none
        // that happened before.
        let reconciler = HistoryTimestampReconciler()
        reconciler.recordClockChange(at: 10, deltaSec: 600)
        reconciler.recordClockChange(at: 20, deltaSec: -60)

        // Before both changes: both deltas apply.
        XCTAssertEqual(reconciler.utcDate(pumpTimeSec: 1000, sequenceNum: 5), pumpDate(1000 + 600 - 60))
        // Between them: only the later change applies.
        XCTAssertEqual(reconciler.utcDate(pumpTimeSec: 1000, sequenceNum: 15), pumpDate(1000 - 60))
        // After both: no adjustment.
        XCTAssertEqual(reconciler.utcDate(pumpTimeSec: 1000, sequenceNum: 25), pumpDate(1000))
    }

    func testRecordsTimeChangedLogAsMillisecondsSinceMidnight() {
        // timePrior/timeAfter are milliseconds since local midnight: 01:00:00 -> 02:00:00 is a
        // +3600 s shift for records written before the change.
        let reconciler = HistoryTimestampReconciler()
        reconciler.recordClockChanges(in: [
            TimeChangedHistoryLog(
                pumpTimeSec: 9000,
                sequenceNum: 50,
                timePrior: 3_600_000,
                timeAfter: 7_200_000,
                rawRTC: 0
            )
        ])

        XCTAssertEqual(reconciler.utcDate(pumpTimeSec: 8000, sequenceNum: 49), pumpDate(8000 + 3600))
        XCTAssertEqual(reconciler.utcDate(pumpTimeSec: 9000, sequenceNum: 51), pumpDate(9000))
    }

    func testTimeChangedDeltaRoundsToNearestSecond() {
        let reconciler = HistoryTimestampReconciler()
        reconciler.recordClockChanges(in: [
            TimeChangedHistoryLog(pumpTimeSec: 9000, sequenceNum: 50, timePrior: 0, timeAfter: 1500, rawRTC: 0)
        ])

        XCTAssertEqual(reconciler.utcDate(pumpTimeSec: 8000, sequenceNum: 49), pumpDate(8000 + 2))
    }

    func testRecordsDateChangeLogAsDays() {
        // datePrior/dateAfter are days since the Jan-1-2008 epoch.
        let reconciler = HistoryTimestampReconciler()
        reconciler.recordClockChanges(in: [
            DateChangeHistoryLog(pumpTimeSec: 9000, sequenceNum: 50, datePrior: 100, dateAfter: 101, rawRTCTime: 0)
        ])

        XCTAssertEqual(reconciler.utcDate(pumpTimeSec: 8000, sequenceNum: 49), pumpDate(8000 + 86400))
    }

    func testMidnightCrossingSumsTimeAndDateDeltas() {
        // Moving the clock forward ten minutes across midnight (23:55 -> 00:05) emits a
        // backward TimeChanged (-85800 s) plus a forward DateChange (+86400 s); the true shift
        // is their sum, +600 s.
        let reconciler = HistoryTimestampReconciler()
        reconciler.recordClockChanges(in: [
            TimeChangedHistoryLog(
                pumpTimeSec: 9000,
                sequenceNum: 50,
                timePrior: 86_100_000,
                timeAfter: 300_000,
                rawRTC: 0
            ),
            DateChangeHistoryLog(pumpTimeSec: 9000, sequenceNum: 51, datePrior: 200, dateAfter: 201, rawRTCTime: 0)
        ])

        XCTAssertEqual(reconciler.utcDate(pumpTimeSec: 8000, sequenceNum: 49), pumpDate(8000 + 600))
    }

    func testIgnoresOtherLogTypes() {
        let reconciler = HistoryTimestampReconciler()
        reconciler.recordClockChanges(in: [
            BolusActivatedHistoryLog(pumpTimeSec: 9000, sequenceNum: 50, bolusId: 1, selectedIob: 0, iob: 0, bolusSize: 1.0)
        ])

        XCTAssertEqual(reconciler.utcDate(pumpTimeSec: 8000, sequenceNum: 49), pumpDate(8000))
    }
}
