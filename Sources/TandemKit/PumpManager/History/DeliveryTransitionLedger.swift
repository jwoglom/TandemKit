import Foundation
import LoopKit

/// Every suspend and resume reported to the host, with the span the pump's own record of it can
/// fall in, so a history pass reports only what the live path never did (#333).
public struct DeliveryTransitionLedger: Equatable {
    public enum Kind: String, Equatable {
        case suspend
        case resume
    }

    public struct Entry: Equatable {
        public let kind: Kind
        /// The date the host was given.
        public let date: Date
        /// Where the pump's record of it may lie, on the phone's clock.
        public let earliest: Date
        public let latest: Date
        /// The pump history record this entry accounts for, once matched.
        public var sequenceNum: UInt32?
        /// False for a pump record deliberately left unreported, kept so it is not reconsidered.
        public let isReported: Bool

        public init(kind: Kind, date: Date, earliest: Date, latest: Date, sequenceNum: UInt32?, isReported: Bool) {
            self.kind = kind
            self.date = date
            self.earliest = earliest
            self.latest = latest
            self.sequenceNum = sequenceNum
            self.isReported = isReported
        }
    }

    /// A delivery change the live path saw on the pump and left for history to date. While it is
    /// pending `basalDose` holds a placeholder for status, or `prior` while a temp replaces it, and
    /// `prior` is what the host holds.
    public struct PendingTransition: Equatable {
        /// A temp the pump runs in place of the temp `prior`, as `TempRateRequest` reads it.
        public struct ReplacingTemp: Equatable {
            /// The pump's own record of its start, on the phone's clock.
            public let start: Date
            public let percent: Int
            /// Units per hour: `percent` of the pump's profile rate at detection.
            public let rate: Double

            public init(start: Date, percent: Int, rate: Double) {
                self.start = start
                self.percent = percent
                self.rate = rate
            }
        }

        /// A temp basal here is still open in the host.
        public let prior: UnfinalizedDose
        public let observed: DoseType
        public let detectedAt: Date
        /// The last reading that saw the pump in `prior`'s state. The change happened after this.
        public let lastConfirmed: Date
        public let replacement: ReplacingTemp?

        public init(prior: UnfinalizedDose, observed: DoseType, detectedAt: Date, lastConfirmed: Date, replacement: ReplacingTemp? = nil) {
            self.prior = prior
            self.observed = observed
            self.detectedAt = detectedAt
            self.lastConfirmed = lastConfirmed
            self.replacement = replacement
        }
    }

    /// Pump records older than this are never reported, so entries that can only match them go.
    public static let retention: TimeInterval = .hours(24)

    /// The pump whose sequence numbers `trackedAfter` and the entries refer to.
    public private(set) var pumpSerial: UInt32?
    /// The pump's last record when the driver started watching it. Records up to it may have
    /// been reported live without an entry, so they are never reported, unless dated from `historySince`.
    public private(set) var trackedAfter: UInt32?
    /// Setup's history load: the user has said no host already counts the pump's history from here on.
    public private(set) var historySince: Date?
    public private(set) var entries: [Entry]
    public var pending: PendingTransition?
    /// The last reading that saw the pump in the state the host holds, or will once `pending` is
    /// reported.
    public var lastConfirmedObservation: Date?
    /// The part of a temp basal a pump stop ended, as the host was told. An occlusion leaves the
    /// temp set, and the pump runs it again at a resume before its programmed end, which the stop
    /// does not move.
    public var interruptedTemp: UnfinalizedDose?

    public init(
        pumpSerial: UInt32? = nil,
        trackedAfter: UInt32? = nil,
        historySince: Date? = nil,
        entries: [Entry] = [],
        pending: PendingTransition? = nil,
        lastConfirmedObservation: Date? = nil,
        interruptedTemp: UnfinalizedDose? = nil
    ) {
        self.pumpSerial = pumpSerial
        self.trackedAfter = trackedAfter
        self.historySince = historySince
        self.entries = entries
        self.pending = pending
        self.lastConfirmedObservation = lastConfirmedObservation
        self.interruptedTemp = interruptedTemp
    }

    /// Starts tracking `pumpSerial` after `lastSequenceNum`: on first sight, a replacement pump, or
    /// a log the pump erased. What the host was told stays; which record accounts for it does not.
    public mutating func track(pumpSerial: UInt32, after lastSequenceNum: UInt32) {
        if self.pumpSerial.map({ $0 != pumpSerial }) == true {
            historySince = nil
        }
        self.pumpSerial = pumpSerial
        trackedAfter = lastSequenceNum
        entries = entries.filter(\.isReported).map { entry in
            var entry = entry
            entry.sequenceNum = nil
            return entry
        }
    }

    public func isTracking(pumpSerial: UInt32, lastSequenceNum: UInt32) -> Bool {
        guard self.pumpSerial == pumpSerial, let trackedAfter else { return false }
        return lastSequenceNum >= trackedAfter
    }

    /// Whether a pump record, dated on the phone's clock, may be reported.
    public func isTracked(sequenceNum: UInt32, date: Date) -> Bool {
        guard let trackedAfter else { return false }
        return sequenceNum > trackedAfter || historySince.map { date >= $0 } == true
    }

    /// Reports the pump's suspends and resumes from `date` on, as setup's history load does.
    public mutating func reportHistory(since date: Date) {
        historySince = min(historySince ?? date, date)
    }

    public mutating func record(_ entry: Entry) {
        entries.append(entry)
        entries.sort { $0.date < $1.date }
    }

    public func isHandled(sequenceNum: UInt32) -> Bool {
        entries.contains { $0.sequenceNum == sequenceNum }
    }

    /// Claims the oldest unmatched entry whose span holds a pump record of `kind` at `date`.
    public mutating func match(_ kind: Kind, at date: Date, sequenceNum: UInt32) -> Bool {
        guard let index = entries.firstIndex(where: {
            $0.kind == kind && $0.sequenceNum == nil && $0.isReported && $0.earliest <= date && date <= $0.latest
        }) else {
            return false
        }
        entries[index].sequenceNum = sequenceNum
        return true
    }

    /// Claims for a pump suspend record the host's last report, when that is a suspend at or after the record
    /// with no record of its own: nothing resumed it since, so it is the same suspension.
    public mutating func claimOpenSuspend(from date: Date, sequenceNum: UInt32) -> Bool {
        guard let index = entries.lastIndex(where: \.isReported), entries[index].kind == .suspend,
              entries[index].sequenceNum == nil, entries[index].date >= date
        else {
            return false
        }
        entries[index].sequenceNum = sequenceNum
        return true
    }

    public func lastReported(before date: Date) -> Entry? {
        entries.last { $0.isReported && $0.date < date }
    }

    public mutating func prune(before floor: Date) {
        entries.removeAll { $0.latest < floor }
    }
}

// MARK: - Raw representation

extension DeliveryTransitionLedger: RawRepresentable {
    public typealias RawValue = [String: Any]

    public init?(rawValue: RawValue) {
        self.init(
            pumpSerial: rawValue["pumpSerial"] as? UInt32,
            trackedAfter: rawValue["trackedAfter"] as? UInt32,
            historySince: (rawValue["historySince"] as? TimeInterval).map(Date.init(timeIntervalSinceReferenceDate:)),
            entries: (rawValue["entries"] as? [[String: Any]] ?? []).compactMap(Entry.init(rawValue:)),
            pending: (rawValue["pending"] as? [String: Any]).flatMap(PendingTransition.init(rawValue:)),
            lastConfirmedObservation: (rawValue["lastConfirmedObservation"] as? TimeInterval)
                .map(Date.init(timeIntervalSinceReferenceDate:)),
            interruptedTemp: (rawValue["interruptedTemp"] as? UnfinalizedDose.RawValue).flatMap(UnfinalizedDose.init(rawValue:))
        )
    }

    public var rawValue: RawValue {
        var raw: RawValue = ["entries": entries.map(\.rawValue)]
        raw["pumpSerial"] = pumpSerial
        raw["trackedAfter"] = trackedAfter
        raw["historySince"] = historySince?.timeIntervalSinceReferenceDate
        raw["pending"] = pending?.rawValue
        raw["lastConfirmedObservation"] = lastConfirmedObservation?.timeIntervalSinceReferenceDate
        raw["interruptedTemp"] = interruptedTemp?.rawValue
        return raw
    }
}

extension DeliveryTransitionLedger.Entry: RawRepresentable {
    public typealias RawValue = [String: Any]

    public init?(rawValue: RawValue) {
        guard let kindRaw = rawValue["kind"] as? String,
              let kind = DeliveryTransitionLedger.Kind(rawValue: kindRaw),
              let date = rawValue["date"] as? TimeInterval,
              let earliest = rawValue["earliest"] as? TimeInterval,
              let latest = rawValue["latest"] as? TimeInterval
        else {
            return nil
        }
        self.init(
            kind: kind,
            date: Date(timeIntervalSinceReferenceDate: date),
            earliest: Date(timeIntervalSinceReferenceDate: earliest),
            latest: Date(timeIntervalSinceReferenceDate: latest),
            sequenceNum: rawValue["sequenceNum"] as? UInt32,
            isReported: rawValue["isReported"] as? Bool ?? true
        )
    }

    public var rawValue: RawValue {
        var raw: RawValue = [
            "kind": kind.rawValue,
            "date": date.timeIntervalSinceReferenceDate,
            "earliest": earliest.timeIntervalSinceReferenceDate,
            "latest": latest.timeIntervalSinceReferenceDate,
            "isReported": isReported
        ]
        raw["sequenceNum"] = sequenceNum
        return raw
    }
}

extension DeliveryTransitionLedger.PendingTransition: RawRepresentable {
    public typealias RawValue = [String: Any]

    public init?(rawValue: RawValue) {
        guard let priorRaw = rawValue["prior"] as? UnfinalizedDose.RawValue,
              let prior = UnfinalizedDose(rawValue: priorRaw),
              let observedRaw = rawValue["observed"] as? DoseType.RawValue,
              let observed = DoseType(rawValue: observedRaw),
              let detectedAt = rawValue["detectedAt"] as? TimeInterval,
              let lastConfirmed = rawValue["lastConfirmed"] as? TimeInterval
        else {
            return nil
        }
        let replacement = (rawValue["replacement"] as? [String: Any]).flatMap { raw -> ReplacingTemp? in
            guard let start = raw["start"] as? TimeInterval, let percent = raw["percent"] as? Int, let rate = raw["rate"] as? Double else {
                return nil
            }
            return ReplacingTemp(start: Date(timeIntervalSinceReferenceDate: start), percent: percent, rate: rate)
        }
        self.init(
            prior: prior,
            observed: observed,
            detectedAt: Date(timeIntervalSinceReferenceDate: detectedAt),
            lastConfirmed: Date(timeIntervalSinceReferenceDate: lastConfirmed),
            replacement: replacement
        )
    }

    public var rawValue: RawValue {
        var raw: RawValue = [
            "prior": prior.rawValue,
            "observed": observed.rawValue,
            "detectedAt": detectedAt.timeIntervalSinceReferenceDate,
            "lastConfirmed": lastConfirmed.timeIntervalSinceReferenceDate
        ]
        raw["replacement"] = replacement.map { replacement -> [String: Any] in
            ["start": replacement.start.timeIntervalSinceReferenceDate, "percent": replacement.percent, "rate": replacement.rate]
        }
        return raw
    }
}
