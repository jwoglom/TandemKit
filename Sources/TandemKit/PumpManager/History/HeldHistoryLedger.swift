import Foundation

/// History events no pass could date, by the `raw` they would be reported under. Nothing held reaches the
/// host; an event leaves when a later pass dates it.
public struct HeldHistoryLedger: Equatable {
    public struct Entry: Equatable {
        public let raw: Data
        public let firstHeldAt: Date
        /// Past this its insulin no longer acts, so it stops warning and stops holding basal reconciliation back.
        public let expiresAt: Date
        public var lastHeldAt: Date

        public init(raw: Data, firstHeldAt: Date, expiresAt: Date, lastHeldAt: Date) {
            self.raw = raw
            self.firstHeldAt = firstHeldAt
            self.expiresAt = expiresAt
            self.lastHeldAt = lastHeldAt
        }
    }

    /// A pass or two usually dates what the last could not, once the pump's clock-change record is read.
    public static let warningDelay: TimeInterval = .minutes(15)
    /// The longest insulin action Loop and Trio offer. Counted from when it was first held, by when it had been given.
    public static let insulinActionWindow: TimeInterval = .hours(6)
    /// An expired entry stays while passes still hold its event, or the next pass would start it warning again.
    static let forgetAfterLastHeld: TimeInterval = BolusReportLedger.reportingHorizon
    /// Past a day of BasalDelivery records, so none held is dropped and taken for new when next seen.
    static let limit = 512

    public private(set) var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    /// - Parameters:
    ///   - examined: Every event a pass tried to date this time.
    ///   - held: Those it could not, each with how long after now its delivery may run on (an extended bolus's
    ///     programmed duration).
    public mutating func update(examined: Set<Data>, held: [Data: TimeInterval], now: Date) {
        entries.removeAll { examined.contains($0.raw) && held[$0.raw] == nil }
        for (raw, runsOn) in held.sorted(by: { $0.key.lexicographicallyPrecedes($1.key) }) {
            if let index = entries.firstIndex(where: { $0.raw == raw }) {
                entries[index].lastHeldAt = now
            } else {
                entries.append(Entry(
                    raw: raw,
                    firstHeldAt: now,
                    expiresAt: now.addingTimeInterval(max(0, runsOn) + Self.insulinActionWindow),
                    lastHeldAt: now
                ))
            }
        }
        entries.removeAll { now.timeIntervalSince($0.lastHeldAt) > Self.forgetAfterLastHeld }
        if entries.count > Self.limit {
            entries.sort { $0.firstHeldAt < $1.firstHeldAt }
            entries.removeFirst(entries.count - Self.limit)
        }
    }

    public func isHolding(_ raw: Data, now: Date) -> Bool {
        entries.contains { $0.raw == raw && now < $0.expiresAt }
    }

    public func entriesHeldTooLong(now: Date) -> [Entry] {
        entries.filter { now.timeIntervalSince($0.firstHeldAt) >= Self.warningDelay && now < $0.expiresAt }
    }
}

extension HeldHistoryLedger: RawRepresentable {
    public typealias RawValue = [[String: Any]]

    public init?(rawValue: RawValue) {
        self.init(entries: rawValue.compactMap { raw in
            guard let data = raw["raw"] as? Data,
                  let firstHeldAt = raw["firstHeldAt"] as? TimeInterval,
                  let expiresAt = raw["expiresAt"] as? TimeInterval,
                  let lastHeldAt = raw["lastHeldAt"] as? TimeInterval
            else {
                return nil
            }
            return Entry(
                raw: data,
                firstHeldAt: Date(timeIntervalSinceReferenceDate: firstHeldAt),
                expiresAt: Date(timeIntervalSinceReferenceDate: expiresAt),
                lastHeldAt: Date(timeIntervalSinceReferenceDate: lastHeldAt)
            )
        })
    }

    public var rawValue: RawValue {
        entries.map { entry in
            [
                "raw": entry.raw,
                "firstHeldAt": entry.firstHeldAt.timeIntervalSinceReferenceDate,
                "expiresAt": entry.expiresAt.timeIntervalSinceReferenceDate,
                "lastHeldAt": entry.lastHeldAt.timeIntervalSinceReferenceDate
            ]
        }
    }
}
