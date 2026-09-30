import Foundation

/// How the boluses the live path could not settle on its own were settled: found in pump
/// history, finalized from it, or finalized with a fallback. For the diagnostics screen only;
/// nothing reads it back to decide a dose.
public struct BolusResolutionLog: Equatable {
    public enum Kind: String, CaseIterable, Equatable {
        /// First report of a bolus the app did not command: pump UI, Control-IQ, or a lost
        /// `InitiateBolus` acknowledgement.
        case pumpBolusFound
        /// A bolus first reported from history while in flight, now reported finalized.
        case pumpBolusFinalized
        /// An app bolus the live path had stopped tracking, finalized from its history record
        /// under its live identity.
        case appBolusFinalizedFromHistory
        /// The pump did not confirm a bolus's volume, so it is held mutable (#328).
        case bolusHeld
        case heldBolusConfirmedByPump
        case heldBolusFinalizedFromHistory
        /// The pump never confirmed the volume (#448, #464).
        case heldBolusFinalizedWithFallback
        /// #424.
        case extendedBolusNotReported
    }

    public struct Event: Equatable {
        /// When the driver decided, on the host clock.
        public let date: Date
        public let kind: Kind
        public let bolusId: Int?
        /// The date the bolus is reported under.
        public let doseDate: Date?
        public let programmedUnits: Double?
        /// Nil while the dose is reported mutable.
        public let deliveredUnits: Double?
        /// What a held bolus is finalized with if the pump never confirms it.
        public let fallbackUnits: Double?
        public let isMutable: Bool
        public let automatic: Bool?
        /// `BolusDeliveryHistoryLog.BolusSource` raw value, when history carried one.
        public let bolusSource: Int?
        public let note: String?

        public init(
            date: Date,
            kind: Kind,
            bolusId: Int?,
            doseDate: Date? = nil,
            programmedUnits: Double? = nil,
            deliveredUnits: Double? = nil,
            fallbackUnits: Double? = nil,
            isMutable: Bool = false,
            automatic: Bool? = nil,
            bolusSource: Int? = nil,
            note: String? = nil
        ) {
            self.date = date
            self.kind = kind
            self.bolusId = bolusId
            self.doseDate = doseDate
            self.programmedUnits = programmedUnits
            self.deliveredUnits = deliveredUnits
            self.fallbackUnits = fallbackUnits
            self.isMutable = isMutable
            self.automatic = automatic
            self.bolusSource = bolusSource
            self.note = note
        }
    }

    public static let retention: TimeInterval = .hours(24)
    /// Bounds the persisted state under Control-IQ, which can bolus many times a day.
    public static let maximumEvents = 100

    /// Start of `counts`, which outlive the events' retention.
    public private(set) var countingSince: Date
    public private(set) var counts: [Kind: Int]
    /// Oldest first.
    public private(set) var events: [Event]

    public init(countingSince: Date, counts: [Kind: Int] = [:], events: [Event] = []) {
        self.countingSince = countingSince
        self.counts = counts
        self.events = events
    }

    public func count(_ kind: Kind) -> Int {
        counts[kind] ?? 0
    }

    public func contains(_ kind: Kind, bolusId: Int) -> Bool {
        events.contains { $0.kind == kind && $0.bolusId == bolusId }
    }

    public mutating func record(_ event: Event) {
        counts[event.kind, default: 0] += 1
        events.append(event)
        prune(now: event.date)
    }

    public mutating func prune(now: Date) {
        events.removeAll { now.timeIntervalSince($0.date) > Self.retention }
        if events.count > Self.maximumEvents {
            events.removeFirst(events.count - Self.maximumEvents)
        }
    }

    public mutating func reset(now: Date) {
        countingSince = now
        counts = [:]
        events = []
    }
}

// MARK: - Raw representation

extension BolusResolutionLog: RawRepresentable {
    public typealias RawValue = [String: Any]

    public init?(rawValue: RawValue) {
        guard let countingSince = rawValue["countingSince"] as? TimeInterval else {
            return nil
        }
        var counts: [Kind: Int] = [:]
        for (key, value) in rawValue["counts"] as? [String: Int] ?? [:] {
            if let kind = Kind(rawValue: key) {
                counts[kind] = value
            }
        }
        self.init(
            countingSince: Date(timeIntervalSinceReferenceDate: countingSince),
            counts: counts,
            events: (rawValue["events"] as? [[String: Any]] ?? []).compactMap(Event.init(rawValue:))
        )
    }

    public var rawValue: RawValue {
        [
            "countingSince": countingSince.timeIntervalSinceReferenceDate,
            "counts": Dictionary(uniqueKeysWithValues: counts.map { ($0.key.rawValue, $0.value) }),
            "events": events.map(\.rawValue)
        ]
    }
}

extension BolusResolutionLog.Event: RawRepresentable {
    public typealias RawValue = [String: Any]

    public init?(rawValue: RawValue) {
        guard let date = rawValue["date"] as? TimeInterval,
              let kindRaw = rawValue["kind"] as? String,
              let kind = BolusResolutionLog.Kind(rawValue: kindRaw)
        else {
            return nil
        }
        self.init(
            date: Date(timeIntervalSinceReferenceDate: date),
            kind: kind,
            bolusId: rawValue["bolusId"] as? Int,
            doseDate: (rawValue["doseDate"] as? TimeInterval).map { Date(timeIntervalSinceReferenceDate: $0) },
            programmedUnits: rawValue["programmedUnits"] as? Double,
            deliveredUnits: rawValue["deliveredUnits"] as? Double,
            fallbackUnits: rawValue["fallbackUnits"] as? Double,
            isMutable: rawValue["isMutable"] as? Bool ?? false,
            automatic: rawValue["automatic"] as? Bool,
            bolusSource: rawValue["bolusSource"] as? Int,
            note: rawValue["note"] as? String
        )
    }

    public var rawValue: RawValue {
        var raw: RawValue = [
            "date": date.timeIntervalSinceReferenceDate,
            "kind": kind.rawValue,
            "isMutable": isMutable
        ]
        raw["bolusId"] = bolusId
        raw["doseDate"] = doseDate?.timeIntervalSinceReferenceDate
        raw["programmedUnits"] = programmedUnits
        raw["deliveredUnits"] = deliveredUnits
        raw["fallbackUnits"] = fallbackUnits
        raw["automatic"] = automatic
        raw["bolusSource"] = bolusSource
        raw["note"] = note
        return raw
    }
}
