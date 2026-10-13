import Foundation

/// What has been reported to the host for each recent bolus, by `bolusId`. The live and history
/// paths key a bolus differently, so without this history would report app boluses twice (#344).
public struct BolusReportLedger: Equatable {
    public enum Origin: String, Equatable {
        case commanded
        case history
    }

    /// Tandem's names for a bolus's up-front and extended parts, which share its `bolusId` and are
    /// reported as two doses.
    public enum Part: String, Equatable {
        case standard
        case extended
    }

    public struct Entry: Equatable {
        public let bolusId: Int
        public let pumpSerial: UInt32?
        public let origin: Origin
        public let part: Part
        public let raw: Data
        /// Trio falls back to dedupe on this, so every report of the bolus reuses it.
        public let eventDate: Date
        public let automatic: Bool
        /// The host never revises a finalized row, so nothing more is sent once this is set.
        public var isFinalized: Bool
        /// What the host counts: the programmed amount while mutable, the delivered amount once
        /// finalized. Nil on an entry recorded before amounts were kept.
        public var units: Double?
        /// An extended part's programmed end on the phone's clock, for the mutable dose batches carry.
        public let programmedEndDate: Date?

        public init(
            bolusId: Int,
            pumpSerial: UInt32?,
            origin: Origin,
            part: Part = .standard,
            raw: Data,
            eventDate: Date,
            automatic: Bool,
            isFinalized: Bool,
            units: Double? = nil,
            programmedEndDate: Date? = nil
        ) {
            self.bolusId = bolusId
            self.pumpSerial = pumpSerial
            self.origin = origin
            self.part = part
            self.raw = raw
            self.eventDate = eventDate
            self.automatic = automatic
            self.isFinalized = isFinalized
            self.units = units
            self.programmedEndDate = programmedEndDate
        }

        /// An entry recorded before the serial was known matches any serial.
        func matches(bolusId: Int, pumpSerial: UInt32) -> Bool {
            self.bolusId == bolusId && (self.pumpSerial == nil || self.pumpSerial == pumpSerial)
        }
    }

    /// A bolus seen on the pump, running, that the app did not start and history has not reported.
    public struct UnreportedBolus: Equatable {
        public let bolusId: Int
        public let pumpSerial: UInt32
        /// On the phone's clock.
        public let startDate: Date
        /// The host's boundary goes no further until history reports it.
        public let holdsBoundaryAt: Date

        public init(bolusId: Int, pumpSerial: UInt32, startDate: Date, holdsBoundaryAt: Date) {
            self.bolusId = bolusId
            self.pumpSerial = pumpSerial
            self.startDate = startDate
            self.holdsBoundaryAt = holdsBoundaryAt
        }
    }

    public static let reportingHorizon: TimeInterval = .hours(24)
    /// Past the horizon: history dates an app bolus at activation on the pump's clock, which can be
    /// after its entry, and one pruned too soon is reported again as a pump-UI bolus.
    public static let retention: TimeInterval = reportingHorizon + .hours(12)

    /// When this build started recording commanded boluses.
    public let trackingSince: Date

    public private(set) var entries: [Entry]
    public private(set) var unreported: [UnreportedBolus]

    public init(trackingSince: Date, entries: [Entry] = [], unreported: [UnreportedBolus] = []) {
        self.trackingSince = trackingSince
        self.entries = entries
        self.unreported = unreported
    }

    public func entry(bolusId: Int, pumpSerial: UInt32, part: Part = .standard) -> Entry? {
        entries.last { $0.part == part && $0.matches(bolusId: bolusId, pumpSerial: pumpSerial) }
    }

    /// Whether the host has been told of either part of the bolus.
    public func hasEntry(bolusId: Int, pumpSerial: UInt32) -> Bool {
        entries.contains { $0.matches(bolusId: bolusId, pumpSerial: pumpSerial) }
    }

    /// Extended parts the host holds as mutable.
    public var heldExtendedParts: [Entry] {
        entries.filter { $0.part == .extended && !$0.isFinalized }
    }

    /// Only another pump's history could report a bolus seen on it.
    public func boundaryHold(pumpSerial: UInt32?) -> Date? {
        unreported.filter { $0.pumpSerial == pumpSerial }.map(\.holdsBoundaryAt).min()
    }

    /// Recorded as its report goes out, so the boundary is held for it no longer.
    public mutating func record(_ entry: Entry) {
        entries.removeAll { $0.bolusId == entry.bolusId && $0.pumpSerial == entry.pumpSerial && $0.part == entry.part }
        entries.append(entry)
        dropUnreported(matching: entry)
    }

    public mutating func markFinalized(raw: Data, units: Double) {
        guard let index = entries.lastIndex(where: { $0.raw == raw }) else {
            return
        }
        entries[index].isFinalized = true
        entries[index].units = units
        dropUnreported(matching: entries[index])
    }

    /// What the host counts for the boluses reported since `date`, or nil when the ledger can't
    /// say: it started later, or holds an entry from then without an amount.
    public func reportedUnits(since date: Date) -> Double? {
        guard trackingSince <= date else {
            return nil
        }
        var total = 0.0
        for entry in entries where entry.eventDate >= date {
            guard let units = entry.units else {
                return nil
            }
            total += units
        }
        return total
    }

    /// No-op for a bolus this ledger already has an entry for.
    public mutating func noteUnreported(_ bolus: UnreportedBolus) {
        guard !hasEntry(bolusId: bolus.bolusId, pumpSerial: bolus.pumpSerial),
              !unreported.contains(where: { $0.bolusId == bolus.bolusId && $0.pumpSerial == bolus.pumpSerial })
        else {
            return
        }
        unreported.append(bolus)
    }

    public mutating func prune(now: Date) {
        entries.removeAll { now.timeIntervalSince($0.eventDate) > Self.retention }
        // Past the horizon history no longer reports it, so nothing else would release the hold.
        unreported.removeAll { now.timeIntervalSince($0.startDate) > Self.reportingHorizon }
    }

    private mutating func dropUnreported(matching entry: Entry) {
        unreported.removeAll { entry.matches(bolusId: $0.bolusId, pumpSerial: $0.pumpSerial) }
    }
}

// MARK: - Raw representation

extension BolusReportLedger: RawRepresentable {
    public typealias RawValue = [String: Any]

    public init?(rawValue: RawValue) {
        guard let trackingSince = rawValue["trackingSince"] as? TimeInterval else {
            return nil
        }
        let entries = (rawValue["entries"] as? [[String: Any]] ?? []).compactMap(Entry.init(rawValue:))
        let unreported = (rawValue["unreported"] as? [[String: Any]] ?? []).compactMap(UnreportedBolus.init(rawValue:))
        self.init(trackingSince: Date(timeIntervalSinceReferenceDate: trackingSince), entries: entries, unreported: unreported)
    }

    public var rawValue: RawValue {
        [
            "trackingSince": trackingSince.timeIntervalSinceReferenceDate,
            "entries": entries.map(\.rawValue),
            "unreported": unreported.map(\.rawValue)
        ]
    }
}

extension BolusReportLedger.UnreportedBolus: RawRepresentable {
    public typealias RawValue = [String: Any]

    public init?(rawValue: RawValue) {
        guard let bolusId = rawValue["bolusId"] as? Int,
              let pumpSerial = rawValue["pumpSerial"] as? UInt32,
              let startDate = rawValue["startDate"] as? TimeInterval,
              let holdsBoundaryAt = rawValue["holdsBoundaryAt"] as? TimeInterval
        else {
            return nil
        }
        self.init(
            bolusId: bolusId,
            pumpSerial: pumpSerial,
            startDate: Date(timeIntervalSinceReferenceDate: startDate),
            holdsBoundaryAt: Date(timeIntervalSinceReferenceDate: holdsBoundaryAt)
        )
    }

    public var rawValue: RawValue {
        [
            "bolusId": bolusId,
            "pumpSerial": pumpSerial,
            "startDate": startDate.timeIntervalSinceReferenceDate,
            "holdsBoundaryAt": holdsBoundaryAt.timeIntervalSinceReferenceDate
        ]
    }
}

extension BolusReportLedger.Entry: RawRepresentable {
    public typealias RawValue = [String: Any]

    public init?(rawValue: RawValue) {
        guard let bolusId = rawValue["bolusId"] as? Int,
              let originRaw = rawValue["origin"] as? String,
              let origin = BolusReportLedger.Origin(rawValue: originRaw),
              let raw = rawValue["raw"] as? Data,
              let eventDate = rawValue["eventDate"] as? TimeInterval
        else {
            return nil
        }
        self.init(
            bolusId: bolusId,
            pumpSerial: rawValue["pumpSerial"] as? UInt32,
            origin: origin,
            part: (rawValue["part"] as? String).flatMap(BolusReportLedger.Part.init(rawValue:)) ?? .standard,
            raw: raw,
            eventDate: Date(timeIntervalSinceReferenceDate: eventDate),
            automatic: rawValue["automatic"] as? Bool ?? false,
            isFinalized: rawValue["isFinalized"] as? Bool ?? false,
            units: rawValue["units"] as? Double,
            programmedEndDate: (rawValue["programmedEndDate"] as? TimeInterval).map(Date.init(timeIntervalSinceReferenceDate:))
        )
    }

    public var rawValue: RawValue {
        var raw: RawValue = [
            "bolusId": bolusId,
            "origin": origin.rawValue,
            "part": part.rawValue,
            "raw": self.raw,
            "eventDate": eventDate.timeIntervalSinceReferenceDate,
            "automatic": automatic,
            "isFinalized": isFinalized
        ]
        raw["pumpSerial"] = pumpSerial
        raw["units"] = units
        raw["programmedEndDate"] = programmedEndDate?.timeIntervalSinceReferenceDate
        return raw
    }
}
