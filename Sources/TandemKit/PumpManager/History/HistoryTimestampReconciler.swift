import Foundation

/// Converts pump history timestamps to UTC `Date`s, correcting records stamped before a clock
/// change.
///
/// A history record's `pumpTimeSec` is the pump's wall clock at the moment the record was
/// written. When that clock is changed, records already in the log keep their old stamps, so a
/// record written before the change is off by the change's delta relative to records written
/// after it. The pump documents each change in the log itself — `TimeChangedHistoryLog` for
/// time-of-day changes, `DateChangeHistoryLog` for date changes — so recording those deltas from
/// a fetched window lets every earlier record be shifted onto the clock in effect now.
final class HistoryTimestampReconciler {
    private var clockChangeDeltas: [(sequenceNum: UInt32, deltaSec: Int)] = []

    /// Record the clock-change events contained in `logs`. Call this with a fetched window
    /// before converting any of its timestamps — a conversion only sees changes recorded so far.
    func recordClockChanges(in logs: [HistoryLog]) {
        for log in logs {
            switch log {
            case let timeChanged as TimeChangedHistoryLog:
                // timePrior/timeAfter are MILLISECONDS since local midnight (verified from pump
                // logs). A change that crosses midnight also emits a DateChangeHistoryLog; the
                // two deltas sum to the true shift.
                let deltaMs = Int(timeChanged.timeAfter) - Int(timeChanged.timePrior)
                recordClockChange(at: timeChanged.sequenceNum, deltaSec: Int((Double(deltaMs) / 1000).rounded()))
            case let dateChanged as DateChangeHistoryLog:
                // datePrior/dateAfter are DAYS since the Jan-1-2008 epoch — see pumpX2's
                // DateChangeHistoryLog.getDatePriorInstant (Dates.fromJan12008EpochDaysToDate).
                let deltaDays = Int(dateChanged.dateAfter) - Int(dateChanged.datePrior)
                recordClockChange(at: dateChanged.sequenceNum, deltaSec: deltaDays * 86400)
            default:
                continue
            }
        }
    }

    /// Record a single clock change: records with sequence numbers below `sequenceNum` were
    /// stamped `deltaSec` behind the clock in effect from `sequenceNum` onwards. (The change
    /// record itself is stamped under the new clock and is not adjusted.)
    func recordClockChange(at sequenceNum: UInt32, deltaSec: Int) {
        clockChangeDeltas.append((sequenceNum, deltaSec))
    }

    /// Convert a record's pump timestamp to a UTC `Date`, applying every recorded clock change
    /// that happened after the record was written.
    ///
    /// `Dates.fromJan12008EpochSecondsToDate` already converts the pump's local-wall-clock
    /// seconds (Tandem 2008 epoch) into a UTC instant — it subtracts the device's UTC offset
    /// internally, and is the same conversion the rest of TandemKit uses (e.g.
    /// `LastBolusStatus.timestampDate`) — so the offset must not be subtracted a second time
    /// here. The pump's clock is kept in sync with the device's local time, so the device offset
    /// is the right one to use.
    func utcDate(pumpTimeSec: UInt32, sequenceNum: UInt32) -> Date {
        Dates.fromJan12008EpochSecondsToDate(TimeInterval(adjustedPumpTimeSec(pumpTimeSec, sequenceNum: sequenceNum)))
    }

    /// Apply the cumulative delta of every clock change recorded after `sequenceNum`.
    private func adjustedPumpTimeSec(_ pumpTimeSec: UInt32, sequenceNum: UInt32) -> Int {
        clockChangeDeltas
            .filter { $0.sequenceNum > sequenceNum }
            .reduce(Int(pumpTimeSec)) { $0 + $1.deltaSec }
    }
}

/// Every date a history pass takes from a record, on the phone's clock: past the pump clock changes
/// among `logs`, then by the pump clock offset (`TandemPumpManager.hostDate(forPumpDate:)`). One per
/// pass; a reconciler shared across passes would apply each clock change once per pass.
struct HistoryRecordDates {
    private let reconciler = HistoryTimestampReconciler()
    private let hostDate: (Date) -> Date

    init(_ logs: [HistoryLog], hostDate: @escaping (Date) -> Date) {
        reconciler.recordClockChanges(in: logs)
        self.hostDate = hostDate
    }

    func phoneDate(of log: HistoryLog) -> Date {
        hostDate(reconciler.utcDate(pumpTimeSec: log.pumpTimeSec, sequenceNum: log.sequenceNum))
    }
}

extension TandemPumpManager {
    func historyRecordDates(_ logs: [HistoryLog]) -> HistoryRecordDates {
        HistoryRecordDates(logs) { [weak self] in self?.hostDate(forPumpDate: $0) ?? $0 }
    }
}
