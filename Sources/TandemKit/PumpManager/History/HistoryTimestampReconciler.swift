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
///
/// A change is carried back only along the clock it changed. A reset, shelf mode (whose wake restarts
/// the clock at 2008) or a stamp that runs back unexplained ends it, and nothing at or below that
/// `clockBreak` is dated.
final class HistoryTimestampReconciler {
    /// `TimeChanged`'s delta is rounded from milliseconds, so a corrected stamp may run back a second
    /// past the change; a reset runs back years.
    static let clockStepTolerance = 2

    private var clockChangeDeltas: [(sequenceNum: UInt32, deltaSec: Int)] = []
    private(set) var clockBreak: UInt32?

    /// Record the clock changes and any clock break among `logs`. Call this with a fetched window
    /// before converting any of its timestamps — a conversion only sees changes recorded so far.
    func recordClockChanges(in logs: [HistoryLog]) {
        for log in logs {
            if let deltaSec = Self.clockChangeDelta(of: log) {
                recordClockChange(at: log.sequenceNum, deltaSec: deltaSec)
            }
        }
        if let found = Self.newestClockBreak(in: logs) {
            clockBreak = max(clockBreak ?? found, found)
        }
    }

    /// Record a single clock change: records with sequence numbers below `sequenceNum` were
    /// stamped `deltaSec` behind the clock in effect from `sequenceNum` onwards. (The change
    /// record itself is stamped under the new clock and is not adjusted.)
    func recordClockChange(at sequenceNum: UInt32, deltaSec: Int) {
        clockChangeDeltas.append((sequenceNum, deltaSec))
    }

    func isDatable(sequenceNum: UInt32) -> Bool {
        clockBreak.map { sequenceNum > $0 } ?? true
    }

    /// Convert a record's pump timestamp to a UTC `Date`, applying every recorded clock change
    /// that happened after the record was written; nil at or below `clockBreak`.
    ///
    /// `Dates.fromJan12008EpochSecondsToDate` already converts the pump's local-wall-clock
    /// seconds (Tandem 2008 epoch) into a UTC instant — it subtracts the device's UTC offset
    /// internally, and is the same conversion the rest of TandemKit uses (e.g.
    /// `LastBolusStatus.timestampDate`) — so the offset must not be subtracted a second time
    /// here. The pump's clock is kept in sync with the device's local time, so the device offset
    /// is the right one to use.
    func utcDate(pumpTimeSec: UInt32, sequenceNum: UInt32) -> Date? {
        guard isDatable(sequenceNum: sequenceNum) else {
            return nil
        }
        return Dates.fromJan12008EpochSecondsToDate(TimeInterval(adjustedPumpTimeSec(pumpTimeSec, sequenceNum: sequenceNum)))
    }

    /// Apply the cumulative delta of every clock change recorded after `sequenceNum`.
    private func adjustedPumpTimeSec(_ pumpTimeSec: UInt32, sequenceNum: UInt32) -> Int {
        clockChangeDeltas
            .filter { $0.sequenceNum > sequenceNum }
            .reduce(Int(pumpTimeSec)) { $0 + $1.deltaSec }
    }

    private static func clockChangeDelta(of log: HistoryLog) -> Int? {
        switch log {
        case let timeChanged as TimeChangedHistoryLog:
            // timePrior/timeAfter are MILLISECONDS since local midnight (verified from pump
            // logs). A change that crosses midnight also emits a DateChangeHistoryLog; the
            // two deltas sum to the true shift.
            let deltaMs = Int(timeChanged.timeAfter) - Int(timeChanged.timePrior)
            return Int((Double(deltaMs) / 1000).rounded())
        case let dateChanged as DateChangeHistoryLog:
            // datePrior/dateAfter are DAYS since the Jan-1-2008 epoch — see pumpX2's
            // DateChangeHistoryLog.getDatePriorInstant (Dates.fromJan12008EpochDaysToDate).
            return (Int(dateChanged.dateAfter) - Int(dateChanged.datePrior)) * 86400
        default:
            return nil
        }
    }

    /// Walks back from the newest record with each change's delta applied below it, so on one clock
    /// the corrected stamps never decrease as sequence numbers do.
    private static func newestClockBreak(in logs: [HistoryLog]) -> UInt32? {
        var shift = 0
        var laterStamp: Int?
        for log in logs.sorted(by: { $0.sequenceNum > $1.sequenceNum }) {
            if log is ArmInitHistoryLog || log is ShelfModeHistoryLog {
                return log.sequenceNum
            }
            // NewDay is stamped at the midnight it marks, which for a date change is the new date's,
            // one record before the DateChange.
            if !(log is NewDayHistoryLog) {
                let stamp = Int(log.pumpTimeSec) + shift
                if let laterStamp, stamp > laterStamp + clockStepTolerance {
                    return log.sequenceNum
                }
                laterStamp = stamp
            }
            shift += clockChangeDelta(of: log) ?? 0
        }
        return nil
    }
}

/// Every date a history pass takes from a record, on the phone's clock: past the pump clock changes
/// among `logs`, then by the pump clock offset (`TandemPumpManager.hostDate(forPumpDate:)`). One per
/// pass; a reconciler shared across passes would apply each clock change once per pass.
struct HistoryRecordDates {
    /// The records given, less those at or below a clock break. A pass works from these alone.
    let logs: [HistoryLog]
    let clockBreak: UInt32?
    private let reconciler = HistoryTimestampReconciler()
    private let hostDate: (Date) -> Date

    init(_ logs: [HistoryLog], hostDate: @escaping (Date) -> Date) {
        reconciler.recordClockChanges(in: logs)
        let clockBreak = reconciler.clockBreak
        self.clockBreak = clockBreak
        self.logs = clockBreak.map { clockBreak in logs.filter { $0.sequenceNum > clockBreak } } ?? logs
        self.hostDate = hostDate
    }

    func isDatable(_ log: HistoryLog) -> Bool {
        reconciler.isDatable(sequenceNum: log.sequenceNum)
    }

    /// A record outside `logs` dates to `distantPast`, below every pass's reporting floor, so a caller
    /// that missed the filter still reports nothing from it.
    func phoneDate(of log: HistoryLog) -> Date {
        reconciler.utcDate(pumpTimeSec: log.pumpTimeSec, sequenceNum: log.sequenceNum).map(hostDate) ?? .distantPast
    }
}

extension TandemPumpManager {
    func historyRecordDates(_ logs: [HistoryLog]) -> HistoryRecordDates {
        let dates = HistoryRecordDates(logs) { [weak self] in self?.hostDate(forPumpDate: $0) ?? $0 }
        if let clockBreak = dates.clockBreak, loggedClockBreaks.insert(clockBreak).inserted {
            logger.warning("Pump history at or below #\(clockBreak) is on a clock lost to a reset or shelf mode; none of it is dated or reported")
        }
        return dates
    }
}
