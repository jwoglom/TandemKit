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
    /// Read by every history pass alongside its own types, since every other record is dated by them.
    static let clockHistoryTypes = [
        TimeChangedHistoryLog.typeId,
        DateChangeHistoryLog.typeId,
        ArmInitHistoryLog.typeId,
        ShelfModeHistoryLog.typeId
    ]

    /// `TimeChanged`'s delta is rounded from milliseconds, so a corrected stamp may run back a second
    /// past the change; a reset runs back years.
    static let clockStepTolerance = 2

    private var clockChangeDeltas: [(sequenceNum: UInt32, deltaSec: Int)] = []
    /// Records up to and including this sequence number were written on a clock the pump has since
    /// lost (a reset, shelf mode, or a stamp that runs back unexplained), so they have no date.
    private(set) var undatableThroughSequenceNum: UInt32?

    /// Record the clock changes among `logs`, and the newest record they cannot date. Call this with a
    /// fetched window before converting any of its timestamps — a conversion only sees changes recorded so far.
    func recordClockChanges(in logs: [HistoryLog]) {
        for log in logs {
            if let deltaSec = Self.clockChangeDelta(of: log) {
                recordClockChange(at: log.sequenceNum, deltaSec: deltaSec)
            }
        }
        if let found = Self.newestUndatableSequenceNum(in: logs) {
            undatableThroughSequenceNum = max(undatableThroughSequenceNum ?? found, found)
        }
    }

    /// Record a single clock change: records with sequence numbers below `sequenceNum` were
    /// stamped `deltaSec` behind the clock in effect from `sequenceNum` onwards. (The change
    /// record itself is stamped under the new clock and is not adjusted.)
    func recordClockChange(at sequenceNum: UInt32, deltaSec: Int) {
        clockChangeDeltas.append((sequenceNum, deltaSec))
    }

    func isDatable(sequenceNum: UInt32) -> Bool {
        undatableThroughSequenceNum.map { sequenceNum > $0 } ?? true
    }

    /// Convert a record's pump timestamp to a UTC `Date`, applying every recorded clock change
    /// that happened after the record was written; nil through `undatableThroughSequenceNum`.
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
        Int(pumpTimeSec) + recordedDeltaSec(after: sequenceNum, through: .max)
    }

    /// The clock changes recorded after record `lower` and no later than record `upper`, summed.
    func recordedDeltaSec(after lower: UInt32, through upper: UInt32) -> Int {
        clockChangeDeltas
            .filter { lower < $0.sequenceNum && $0.sequenceNum <= upper }
            .reduce(0) { $0 + $1.deltaSec }
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
    private static func newestUndatableSequenceNum(in logs: [HistoryLog]) -> UInt32? {
        var shift = 0
        var laterStamp: Int?
        // A run of change records is bounded by its latest stamp: the pump stamps its last at the final time
        // and faketandem every one, but a DateChange can carry the old time of day, so no stamp is the bound.
        var changeRun: (shift: Int, latest: Int)?
        for log in logs.sorted(by: { $0.sequenceNum > $1.sequenceNum }) {
            if log is ArmInitHistoryLog || log is ShelfModeHistoryLog {
                return log.sequenceNum
            }
            if let delta = clockChangeDelta(of: log) {
                let run = changeRun ?? (shift: shift, latest: Int.min)
                changeRun = (run.shift, max(run.latest, Int(log.pumpTimeSec) + run.shift))
                shift += delta
                continue
            }
            // NewDay is stamped at its new date's midnight, a record before the DateChange.
            if log is NewDayHistoryLog {
                continue
            }
            let stamp = Int(log.pumpTimeSec) + shift
            if let bound = [laterStamp, changeRun?.latest].compactMap({ $0 }).min(), stamp > bound + clockStepTolerance {
                return log.sequenceNum
            }
            laterStamp = stamp
            changeRun = nil
        }
        return nil
    }
}

/// Dates a pass's records on the phone's clock, each by its age on the pump's at the anchors either side of it.
/// One per pass; a reconciler shared across passes would apply each clock change once per pass.
struct HistoryRecordDates {
    enum Placement: Equatable {
        case dated(Date)
        /// On no clock the anchors either side of it agree on. It was written by `notAfter`.
        case held(notAfter: Date)
    }

    /// A date this far past the anchor above its record is not that record's.
    static let tolerance = TandemPumpManagerState.pumpClockStepThreshold
    /// Two clocks that both place a record are told apart only when they differ by more than this.
    static let ambiguityLimit = TandemPumpManagerState.pumpClockSkewThreshold

    /// The records given, less those through `undatableThroughSequenceNum`. A pass works from these alone.
    let logs: [HistoryLog]
    let undatableThroughSequenceNum: UInt32?
    private let reconciler = HistoryTimestampReconciler()
    private let anchors: [PumpClockAnchor]
    private let now: Date?
    private let hostDate: (Date) -> Date

    /// - Parameters:
    ///   - anchors: Oldest first.
    ///   - now: The phone's time, which no record is dated past. Nil leaves a date unchecked.
    ///   - hostDate: With no anchor, takes a date on the pump's clock as it runs now to the phone's.
    init(_ logs: [HistoryLog], anchors: [PumpClockAnchor] = [], now: Date? = nil, hostDate: @escaping (Date) -> Date) {
        reconciler.recordClockChanges(in: logs)
        let undatableThrough = reconciler.undatableThroughSequenceNum
        undatableThroughSequenceNum = undatableThrough
        self.logs = undatableThrough.map { undatableThrough in logs.filter { $0.sequenceNum > undatableThrough } } ?? logs
        self.anchors = anchors
        self.now = now
        self.hostDate = hostDate
    }

    func isDatable(_ log: HistoryLog) -> Bool {
        reconciler.isDatable(sequenceNum: log.sequenceNum)
    }

    func isHeld(_ log: HistoryLog) -> Bool {
        if case .held = placement(pumpTimeSec: log.pumpTimeSec, sequenceNum: log.sequenceNum) {
            return true
        }
        return false
    }

    /// A record outside `logs` dates to `distantPast`, below every pass's reporting floor, and a held one to
    /// `distantFuture`, ahead of the phone: a caller that missed either filter still reports nothing from it.
    func phoneDate(of log: HistoryLog) -> Date {
        phoneDate(pumpTimeSec: log.pumpTimeSec, sequenceNum: log.sequenceNum)
    }

    func phoneDate(pumpTimeSec: UInt32, sequenceNum: UInt32) -> Date {
        switch placement(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum) {
        case let .dated(date)?:
            return date
        case .held?:
            return .distantFuture
        case nil:
            return .distantPast
        }
    }

    /// The latest a record can have been written: its date, or for a held one the anchor above it. Nil if undatable.
    func latestPossibleDate(of log: HistoryLog) -> Date? {
        switch placement(pumpTimeSec: log.pumpTimeSec, sequenceNum: log.sequenceNum) {
        case let .dated(date)?:
            return date
        case let .held(notAfter)?:
            return notAfter
        case nil:
            return nil
        }
    }

    /// Nil for a record that is held or undatable.
    func date(of log: HistoryLog) -> Date? {
        if case let .dated(date) = placement(pumpTimeSec: log.pumpTimeSec, sequenceNum: log.sequenceNum) {
            return date
        }
        return nil
    }

    /// On the clock of the anchor above the record or of the one below; where the pump's own records do not
    /// explain how the two differ, on whichever puts it between them. Nil through `undatableThroughSequenceNum`.
    func placement(pumpTimeSec: UInt32, sequenceNum: UInt32) -> Placement? {
        guard reconciler.isDatable(sequenceNum: sequenceNum) else {
            return nil
        }
        let upper = anchors.first { $0.sequenceNum >= sequenceNum }
        let lower = anchors.last { $0.sequenceNum < sequenceNum }
        let byUpper = upper.map { anchor -> Date in
            let carried = Int(pumpTimeSec) + reconciler.recordedDeltaSec(after: sequenceNum, through: anchor.sequenceNum)
            return anchor.phoneDate.addingTimeInterval(TimeInterval(carried - Int(anchor.pumpTimeSec)))
        }
        let byLower = lower.map { anchor -> Date in
            let carriedBack = Int(pumpTimeSec) - reconciler.recordedDeltaSec(after: anchor.sequenceNum, through: sequenceNum)
            return anchor.phoneDate.addingTimeInterval(TimeInterval(carriedBack - Int(anchor.pumpTimeSec)))
        }

        let notAfter = upper?.phoneDate ?? now
        let latest = notAfter?.addingTimeInterval(Self.tolerance) ?? .distantFuture
        let held = Placement.held(notAfter: notAfter ?? .distantFuture)
        func placed(_ date: Date) -> Placement {
            date <= latest ? .dated(date) : held
        }

        switch (byUpper, byLower) {
        case (nil, nil):
            return placed(pumpDate(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum).map(hostDate) ?? .distantPast)
        case let (date?, nil), let (nil, date?):
            return placed(date)
        case let (byUpper?, byLower?):
            let apart = abs(byUpper.timeIntervalSince(byLower))
            guard apart > Self.tolerance, let lower else {
                return placed(byUpper)
            }
            // Only between two clocks: a stamp before the anchor below it on one clock is just an early stamp.
            let earliest = lower.phoneDate.addingTimeInterval(-Self.tolerance)
            switch (earliest <= byUpper && byUpper <= latest, earliest <= byLower && byLower <= latest) {
            case (true, false):
                return .dated(byUpper)
            case (false, true):
                return .dated(byLower)
            case (true, true):
                // The later date counts more of its insulin as still acting; further apart, neither is safe to pick.
                return apart <= Self.ambiguityLimit ? .dated(max(byUpper, byLower)) : held
            case (false, false):
                return held
            }
        }
    }

    /// On the pump's clock as it runs now, which `TandemPumpManager.hostDate(forPumpDate:)` takes; nil
    /// through `undatableThroughSequenceNum`.
    func pumpDate(pumpTimeSec: UInt32, sequenceNum: UInt32) -> Date? {
        reconciler.utcDate(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum)
    }
}

extension TandemPumpManager {
    func historyRecordDates(_ logs: [HistoryLog]) -> HistoryRecordDates {
        let offset = state.pumpClockOffset
        let dates = HistoryRecordDates(
            logs,
            anchors: state.pumpClockAnchors.anchors(pumpSerial: historyLogStoreSerial?.rawValue),
            now: now
        ) { $0.addingTimeInterval(-offset) }
        if let undatableThrough = dates.undatableThroughSequenceNum, loggedUndatableHistory.insert(undatableThrough).inserted {
            logger.warning("Pump history through #\(undatableThrough) is on a clock lost to a reset or shelf mode; none of it is dated or reported")
        }
        return dates
    }

    /// The session store's datable records of `typeIds` in `range` dated `since` or later, dated by the
    /// clock records in `range` alongside them. `range` is above the undatable floor.
    func datedHistory(
        ofTypes typeIds: [Int],
        in range: ClosedRange<UInt32>,
        since: Date? = nil,
        pumpSerial serial: HistoryLogSyncIdentifier.PumpSerial
    ) throws -> (logs: [HistoryLog], dates: HistoryRecordDates) {
        let wanted = Set(typeIds)
        let types = wanted.union(HistoryTimestampReconciler.clockHistoryTypes)
        let dates = try historyRecordDates(historyLogStore.logs(pumpSerial: serial.rawValue, ofTypes: Array(types), in: range).map { $0.parsed() })
        let logs = dates.logs.filter { log in
            wanted.contains(log.typeId) && since.map { dates.phoneDate(of: log) >= $0 } ?? true
        }
        return (logs, dates)
    }

    /// What the session store holds above the undatable floor.
    var reportableHistoryRange: ClosedRange<UInt32>? {
        guard let serial = historyLogStoreSerial,
              let oldest = try? historyLogStore.oldest(pumpSerial: serial.rawValue)?.sequenceNum,
              let newest = try? historyLogStore.newest(pumpSerial: serial.rawValue)?.sequenceNum
        else {
            return nil
        }
        return state.historyBackfill.map { $0.readable(oldest ... newest) } ?? oldest ... newest
    }
}
