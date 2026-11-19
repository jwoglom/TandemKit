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
        let before = 200 * day + 86000
        reconciler.recordClockChanges(in: [
            record(before, 49),
            TimeChangedHistoryLog(
                pumpTimeSec: UInt32(200 * day + 300),
                sequenceNum: 50,
                timePrior: 86_100_000,
                timeAfter: 300_000,
                rawRTC: 0
            ),
            DateChangeHistoryLog(pumpTimeSec: UInt32(201 * day + 300), sequenceNum: 51, datePrior: 200, dateAfter: 201, rawRTCTime: 0)
        ])

        XCTAssertNil(reconciler.clockBreak)
        XCTAssertEqual(reconciler.utcDate(pumpTimeSec: UInt32(before), sequenceNum: 49), pumpDate(before + 600))
    }

    func testIgnoresOtherLogTypes() {
        let reconciler = HistoryTimestampReconciler()
        reconciler.recordClockChanges(in: [
            BolusActivatedHistoryLog(pumpTimeSec: 9000, sequenceNum: 50, bolusId: 1, selectedIob: 0, iob: 0, bolusSize: 1.0)
        ])

        XCTAssertEqual(reconciler.utcDate(pumpTimeSec: 8000, sequenceNum: 49), pumpDate(8000))
    }

    // MARK: - Clock breaks

    func testChangesAfterAShelfModeWakeAreNotCarriedBackToThePreviousUse() {
        let reconciler = HistoryTimestampReconciler()
        reconciler.recordClockChanges(in: shelfModeWake())

        XCTAssertEqual(reconciler.clockBreak, 103)
        XCTAssertNil(reconciler.utcDate(pumpTimeSec: UInt32(previousUseStamp), sequenceNum: 100))
        XCTAssertNil(reconciler.utcDate(pumpTimeSec: 212, sequenceNum: 103))
        XCTAssertEqual(reconciler.utcDate(pumpTimeSec: 219, sequenceNum: 104), pumpDate(6800 * day + 219 + 46181))
        XCTAssertEqual(reconciler.utcDate(pumpTimeSec: UInt32(4383 * day + 3819), sequenceNum: 107), pumpDate(6800 * day + 50000))
    }

    func testStampRunningBackWithNoChangeRecordIsABreak() {
        let reconciler = HistoryTimestampReconciler()
        reconciler.recordClockChanges(in: [
            record(previousUseStamp, 1),
            record(100, 2),
            DateChangeHistoryLog(pumpTimeSec: UInt32(6800 * day + 100), sequenceNum: 3, datePrior: 0, dateAfter: 6800, rawRTCTime: 0),
            record(6800 * day + 200, 4)
        ])

        XCTAssertEqual(reconciler.clockBreak, 1)
        XCTAssertNil(reconciler.utcDate(pumpTimeSec: UInt32(previousUseStamp), sequenceNum: 1))
        XCTAssertEqual(reconciler.utcDate(pumpTimeSec: 100, sequenceNum: 2), pumpDate(6800 * day + 100))
    }

    func testBreakIsFoundWithoutTheResetRecords() {
        // The basal pass reads by raw stamp, which leaves ArmInit's 2008 one out.
        let reconciler = HistoryTimestampReconciler()
        reconciler.recordClockChanges(in: shelfModeWake().filter { !($0 is ShelfModeHistoryLog || $0 is ArmInitHistoryLog) })

        XCTAssertEqual(reconciler.clockBreak, 100)
    }

    func testOneClockWithForwardAndBackwardChangesHasNoBreak() {
        let reconciler = HistoryTimestampReconciler()
        reconciler.recordClockChanges(in: [
            record(6800 * day + 1000, 1),
            TimeChangedHistoryLog(pumpTimeSec: UInt32(6800 * day + 4600), sequenceNum: 2, timePrior: 1_000_000, timeAfter: 4_600_000, rawRTC: 0),
            record(6800 * day + 4700, 3),
            TimeChangedHistoryLog(pumpTimeSec: UInt32(6800 * day + 1100), sequenceNum: 4, timePrior: 4_700_000, timeAfter: 1_100_000, rawRTC: 0),
            record(6800 * day + 1200, 5)
        ])

        XCTAssertNil(reconciler.clockBreak)
        XCTAssertEqual(reconciler.utcDate(pumpTimeSec: UInt32(6800 * day + 1000), sequenceNum: 1), pumpDate(6800 * day + 1000))
    }

    func testRecordDatesLeaveOutRecordsAtOrBelowTheBreak() {
        let logs = shelfModeWake()
        let dates = HistoryRecordDates(logs) { $0 }

        XCTAssertEqual(dates.clockBreak, 103)
        XCTAssertEqual(dates.logs.map(\.sequenceNum), logs.map(\.sequenceNum).filter { $0 > 103 })
        XCTAssertEqual(dates.phoneDate(of: logs[0]), .distantPast)
    }

    private let day = 86400
    private let previousUseStamp = 6600 * 86400 + 36000

    private func record(_ pumpTimeSec: Int, _ sequenceNum: UInt32) -> HistoryLog {
        BolusActivatedHistoryLog(pumpTimeSec: UInt32(pumpTimeSec), sequenceNum: sequenceNum, bolusId: 1, selectedIob: 0, iob: 0, bolusSize: 1)
    }

    /// A Mobi's history across shelf mode: its clock restarts at 2008 on waking, the firmware moves the
    /// date to 2020 (day 4383), and setup an hour later writes the date and time.
    private func shelfModeWake() -> [HistoryLog] {
        [
            record(previousUseStamp, 100),
            ShelfModeHistoryLog(
                pumpTimeSec: UInt32(previousUseStamp + 60),
                sequenceNum: 101,
                msecSinceReset: 0,
                lipoIbc: 0,
                lipoAbc: 0,
                lipoCurrent: 0,
                lipoRemCap: 0,
                lipoMv: 0
            ),
            NewDayHistoryLog(pumpTimeSec: 0, sequenceNum: 102, commandedBasalRate: 0, featuresBitmask: 0, featureBitmaskIndex: 0),
            ArmInitHistoryLog(cargo: HistoryLog.fillCargo(Bytes.combine(
                HistoryLog.typeIdBytes(ArmInitHistoryLog.typeId),
                Bytes.toUint32(212),
                Bytes.toUint32(103)
            ))),
            record(219, 104),
            NewDayHistoryLog(pumpTimeSec: UInt32(4383 * day), sequenceNum: 105, commandedBasalRate: 0, featuresBitmask: 0, featureBitmaskIndex: 0),
            DateChangeHistoryLog(pumpTimeSec: UInt32(4383 * day + 219), sequenceNum: 106, datePrior: 0, dateAfter: 4383, rawRTCTime: 0),
            record(4383 * day + 3819, 107),
            NewDayHistoryLog(pumpTimeSec: UInt32(6800 * day), sequenceNum: 108, commandedBasalRate: 0, featuresBitmask: 0, featureBitmaskIndex: 0),
            DateChangeHistoryLog(pumpTimeSec: UInt32(6800 * day + 3819), sequenceNum: 109, datePrior: 4383, dateAfter: 6800, rawRTCTime: 0),
            TimeChangedHistoryLog(pumpTimeSec: UInt32(6800 * day + 50000), sequenceNum: 110, timePrior: 3_819_000, timeAfter: 50_000_000, rawRTC: 0)
        ]
    }
}
