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

    /// A delivery change the live path saw on the pump and left for history to date. Until it is
    /// resolved `basalDose` holds a placeholder starting at `detectedAt`.
    public struct PendingTransition: Equatable {
        /// The dose the host held before the change; a temp basal here is still open in the host.
        public let prior: UnfinalizedDose
        /// What the pump reports now.
        public var observed: DoseType
        public let detectedAt: Date
        /// The last time the pump was seen in `prior`'s state. The change happened after this.
        public let lastConfirmed: Date

        public init(prior: UnfinalizedDose, observed: DoseType, detectedAt: Date, lastConfirmed: Date) {
            self.prior = prior
            self.observed = observed
            self.detectedAt = detectedAt
            self.lastConfirmed = lastConfirmed
        }

        public static func == (lhs: PendingTransition, rhs: PendingTransition) -> Bool {
            let (a, b) = (lhs.prior, rhs.prior)
            return lhs.observed == rhs.observed && lhs.detectedAt == rhs.detectedAt && lhs.lastConfirmed == rhs.lastConfirmed
                && a.type == b.type && a.value == b.value && a.startDate == b.startDate
                && a.estimatedEndDate == b.estimatedEndDate && a.tempRateId == b.tempRateId && a.bolusId == b.bolusId
                && a.insulinType == b.insulinType && a.automatic == b.automatic
        }
    }

    public static let retention: TimeInterval = .hours(24)

    /// When this build started recording. A history record older than this may have been reported
    /// live without an entry, so it is never reported.
    public let trackingSince: Date
    public private(set) var entries: [Entry]
    public var pending: PendingTransition?
    /// The last time the live path saw the pump in the state it had reported.
    public var lastConfirmedObservation: Date?

    public init(
        trackingSince: Date,
        entries: [Entry] = [],
        pending: PendingTransition? = nil,
        lastConfirmedObservation: Date? = nil
    ) {
        self.trackingSince = trackingSince
        self.entries = entries
        self.pending = pending
        self.lastConfirmedObservation = lastConfirmedObservation
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

    /// The last suspend or resume the host was given before `date`.
    public func lastReported(before date: Date) -> Entry? {
        entries.last { $0.isReported && $0.date < date }
    }

    public mutating func prune(now: Date) {
        entries.removeAll { now.timeIntervalSince($0.date) > Self.retention }
    }
}

// MARK: - Raw representation

extension DeliveryTransitionLedger: RawRepresentable {
    public typealias RawValue = [String: Any]

    public init?(rawValue: RawValue) {
        guard let trackingSince = rawValue["trackingSince"] as? TimeInterval else {
            return nil
        }
        self.init(
            trackingSince: Date(timeIntervalSinceReferenceDate: trackingSince),
            entries: (rawValue["entries"] as? [[String: Any]] ?? []).compactMap(Entry.init(rawValue:)),
            pending: (rawValue["pending"] as? [String: Any]).flatMap(PendingTransition.init(rawValue:)),
            lastConfirmedObservation: (rawValue["lastConfirmedObservation"] as? TimeInterval)
                .map(Date.init(timeIntervalSinceReferenceDate:))
        )
    }

    public var rawValue: RawValue {
        var raw: RawValue = [
            "trackingSince": trackingSince.timeIntervalSinceReferenceDate,
            "entries": entries.map(\.rawValue)
        ]
        raw["pending"] = pending?.rawValue
        raw["lastConfirmedObservation"] = lastConfirmedObservation?.timeIntervalSinceReferenceDate
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
        self.init(
            prior: prior,
            observed: observed,
            detectedAt: Date(timeIntervalSinceReferenceDate: detectedAt),
            lastConfirmed: Date(timeIntervalSinceReferenceDate: lastConfirmed)
        )
    }

    public var rawValue: RawValue {
        [
            "prior": prior.rawValue,
            "observed": observed.rawValue,
            "detectedAt": detectedAt.timeIntervalSinceReferenceDate,
            "lastConfirmed": lastConfirmed.timeIntervalSinceReferenceDate
        ]
    }
}
