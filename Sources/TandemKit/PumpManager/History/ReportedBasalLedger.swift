import Foundation
import LoopKit

/// Every non-bolus row the driver has given the host, kept as the host keeps them, so a history
/// pass can tell what basal the host counts at any instant and compare it with what the pump
/// delivered (`PumpBasalTimeline`). Rows are folded the way Trio's pump history stores them; a
/// basal correction lands here too, so a second pass over the same history finds nothing.
public struct ReportedBasalLedger: Equatable {
    public enum Kind: String, Equatable {
        case tempBasal
        /// A `.basal` marker: the host's schedule from here.
        case basal
        case suspend
        case resume
    }

    public struct Row: Equatable {
        public let kind: Kind
        public let raw: Data
        /// The event date, which the host keys the row on.
        public let date: Date
        public var end: Date
        /// Units per hour.
        public var rate: Double
        public var isMutable: Bool
        public var tempRateId: Int?

        public init(kind: Kind, raw: Data, date: Date, end: Date, rate: Double, isMutable: Bool, tempRateId: Int? = nil) {
            self.kind = kind
            self.raw = raw
            self.date = date
            self.end = end
            self.rate = rate
            self.isMutable = isMutable
            self.tempRateId = tempRateId
        }
    }

    /// What the host counts at an instant, and from which row.
    public struct HostBasal: Equatable {
        public enum Source: Equatable {
            /// No row, a `.basal` marker, or a temp basal that has ended.
            case schedule
            case suspended
            case tempBasal(Row)
        }

        public let rate: Double
        public let source: Source
    }

    /// Past the 24 h a history pass compares, and the hours a temp basal can run before it.
    public static let retention: TimeInterval = .hours(36)

    /// When this build started recording what it reports; nothing before it is compared.
    public let trackingSince: Date
    public private(set) var rows: [Row]
    /// The pump `reconciledThrough` counts on.
    public private(set) var pumpSerial: UInt32?
    /// The last 279 a reporting pass is done with; later passes start after it.
    public private(set) var reconciledThrough: UInt32?

    public init(trackingSince: Date, rows: [Row] = [], pumpSerial: UInt32? = nil, reconciledThrough: UInt32? = nil) {
        self.trackingSince = trackingSince
        self.rows = rows
        self.pumpSerial = pumpSerial
        self.reconciledThrough = reconciledThrough
    }

    /// On first sight, a replacement pump, or a log the pump erased, which numbers from scratch.
    public mutating func track(pumpSerial: UInt32, after lastSequenceNum: UInt32?) {
        self.pumpSerial = pumpSerial
        reconciledThrough = lastSequenceNum
    }

    public func isTracking(pumpSerial: UInt32, lastSequenceNum: UInt32) -> Bool {
        self.pumpSerial == pumpSerial && (reconciledThrough ?? 0) <= lastSequenceNum
    }

    public mutating func reconcile(through sequenceNum: UInt32) {
        reconciledThrough = max(reconciledThrough ?? sequenceNum, sequenceNum)
    }

    /// One `hasNewPumpEvents` batch. Matched by `raw`, then by date and kind; a matched row
    /// changes only while it is mutable, and a replacing batch drops every mutable row it leaves out.
    public mutating func record(_ events: [NewPumpEvent], replacePendingEvents: Bool, tempRateId: (DoseEntry) -> Int? = { _ in nil }) {
        var asserted = Set<Int>()
        for event in events {
            guard let dose = event.dose, let kind = Self.kind(of: dose.type) else { continue }
            let end = kind == .tempBasal ? dose.endDate : event.date
            let rate = kind == .tempBasal || kind == .basal ? dose.unitsPerHour : 0
            let match = rows.firstIndex { $0.raw == event.raw }
                ?? rows.firstIndex { $0.date == event.date && $0.kind == kind }
            if let match {
                asserted.insert(match)
                guard rows[match].isMutable else { continue }
                rows[match].end = end
                rows[match].rate = rate
                rows[match].isMutable = dose.isMutable
                rows[match].tempRateId = tempRateId(dose) ?? rows[match].tempRateId
                continue
            }
            rows.append(Row(
                kind: kind,
                raw: event.raw,
                date: event.date,
                end: end,
                rate: rate,
                isMutable: dose.isMutable,
                tempRateId: kind == .tempBasal ? tempRateId(dose) : nil
            ))
            asserted.insert(rows.count - 1)
        }

        if replacePendingEvents {
            rows = rows.enumerated().filter { !$0.element.isMutable || asserted.contains($0.offset) }.map(\.element)
        }
    }

    private static func kind(of type: DoseType) -> Kind? {
        switch type {
        case .tempBasal: .tempBasal
        case .basal: .basal
        case .suspend: .suspend
        case .resume: .resume
        default: nil
        }
    }

    public mutating func prune(now: Date) {
        let floor = now.addingTimeInterval(-Self.retention)
        rows.removeAll { !$0.isMutable && max($0.date, $0.end) < floor }
    }

    /// As Trio's IOB folds its rows: after a suspend, nothing until the resume; otherwise the
    /// latest basal row starting at or before `date`, a temp basal until its end, and the host's
    /// schedule for a marker, an ended temp basal or no row.
    public func hostBasal(at date: Date, schedule: HostBasalSchedule) -> HostBasal {
        if let transition = latest(before: date, of: [.suspend, .resume]), transition.kind == .suspend {
            return HostBasal(rate: 0, source: .suspended)
        }
        if let row = latest(before: date, of: [.tempBasal, .basal]), row.kind == .tempBasal, date < row.end {
            return HostBasal(rate: row.rate, source: .tempBasal(row))
        }
        return HostBasal(rate: schedule.rate(at: date), source: .schedule)
    }

    /// Of two rows at one date, the later recorded; Trio leaves the order between them undefined.
    private func latest(before date: Date, of kinds: Set<Kind>) -> Row? {
        rows.enumerated()
            .filter { kinds.contains($0.element.kind) && $0.element.date <= date }
            .max { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }?
            .element
    }

    /// Where what the host counts may change inside `interval`: row edges and schedule changes.
    public func changes(in interval: DateInterval, schedule: HostBasalSchedule, includingCorrections: Bool = true) -> [Date] {
        let edges = rows
            .filter { includingCorrections || correctedSequenceNum(of: $0) == nil }
            .flatMap { [$0.date, $0.end] } + schedule.changes(in: interval)
        return Set(edges.filter { interval.start < $0 && $0 < interval.end }).sorted()
    }

    /// The 279 a basal correction on the tracked pump was reported for.
    public func correctedSequenceNum(of row: Row) -> UInt32? {
        guard let identifier = HistoryLogSyncIdentifier.decode(row.raw), identifier.scheme == .logSequence,
              identifier.pumpSerial.rawValue == pumpSerial
        else {
            return nil
        }
        return identifier.identifier
    }

    /// Units the host counts over `interval`.
    public func hostUnits(in interval: DateInterval, schedule: HostBasalSchedule) -> Double {
        let points = [interval.start] + changes(in: interval, schedule: schedule) + [interval.end]
        return zip(points, points.dropFirst()).reduce(0) { total, piece in
            total + hostBasal(at: piece.0, schedule: schedule).rate * piece.1.timeIntervalSince(piece.0) / .hours(1)
        }
    }
}

/// The host's basal schedule on the phone's clock, as `TandemPumpManager.getScheduledBasalRate(at:)` reads it.
public struct HostBasalSchedule {
    public let items: [(startTime: TimeInterval, rate: Double)]
    public let calendar: Calendar

    public init(_ schedule: BasalRateSchedule, calendar: Calendar = .current) {
        items = schedule.items.map { ($0.startTime, $0.value) }.sorted { $0.startTime < $1.startTime }
        self.calendar = calendar
    }

    public func rate(at date: Date) -> Double {
        guard let first = items.first else { return 0 }
        let sinceMidnight = date.timeIntervalSince(calendar.startOfDay(for: date))
        return items.last(where: { $0.startTime < sinceMidnight })?.rate ?? first.rate
    }

    public func changes(in interval: DateInterval) -> [Date] {
        guard items.count > 1 else { return [] }
        var changes: [Date] = []
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            for item in items {
                let date = day.addingTimeInterval(item.startTime)
                if interval.start < date, date < interval.end {
                    changes.append(date)
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return changes
    }
}

// MARK: - Raw representation

extension ReportedBasalLedger: RawRepresentable {
    public typealias RawValue = [String: Any]

    public init?(rawValue: RawValue) {
        guard let trackingSince = rawValue["trackingSince"] as? TimeInterval else {
            return nil
        }
        self.init(
            trackingSince: Date(timeIntervalSinceReferenceDate: trackingSince),
            rows: (rawValue["rows"] as? [[String: Any]] ?? []).compactMap(Row.init(rawValue:)),
            pumpSerial: rawValue["pumpSerial"] as? UInt32,
            reconciledThrough: rawValue["reconciledThrough"] as? UInt32
        )
    }

    public var rawValue: RawValue {
        var raw: RawValue = [
            "trackingSince": trackingSince.timeIntervalSinceReferenceDate,
            "rows": rows.map(\.rawValue)
        ]
        raw["pumpSerial"] = pumpSerial
        raw["reconciledThrough"] = reconciledThrough
        return raw
    }
}

extension ReportedBasalLedger.Row: RawRepresentable {
    public typealias RawValue = [String: Any]

    public init?(rawValue: RawValue) {
        guard let kindRaw = rawValue["kind"] as? String,
              let kind = ReportedBasalLedger.Kind(rawValue: kindRaw),
              let raw = rawValue["raw"] as? Data,
              let date = rawValue["date"] as? TimeInterval,
              let end = rawValue["end"] as? TimeInterval,
              let rate = rawValue["rate"] as? Double
        else {
            return nil
        }
        self.init(
            kind: kind,
            raw: raw,
            date: Date(timeIntervalSinceReferenceDate: date),
            end: Date(timeIntervalSinceReferenceDate: end),
            rate: rate,
            isMutable: rawValue["isMutable"] as? Bool ?? false,
            tempRateId: rawValue["tempRateId"] as? Int
        )
    }

    public var rawValue: RawValue {
        var raw: RawValue = [
            "kind": kind.rawValue,
            "raw": self.raw,
            "date": date.timeIntervalSinceReferenceDate,
            "end": end.timeIntervalSinceReferenceDate,
            "rate": rate,
            "isMutable": isMutable
        ]
        raw["tempRateId"] = tempRateId
        return raw
    }
}
