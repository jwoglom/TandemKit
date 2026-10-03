import Foundation

/// What has been reported to the host for each recent bolus, by `bolusId`. The live and history
/// paths key a bolus differently, so without this history would report app boluses twice (#344).
public struct BolusReportLedger: Equatable {
    public enum Origin: String, Equatable {
        case commanded
        case history
    }

    public struct Entry: Equatable {
        public let bolusId: Int
        public let pumpSerial: UInt32?
        public let origin: Origin
        public let raw: Data
        /// Trio falls back to dedupe on this, so every report of the bolus reuses it.
        public let eventDate: Date
        public let automatic: Bool
        /// The host never revises a finalized row, so nothing more is sent once this is set.
        public var isFinalized: Bool

        public init(
            bolusId: Int,
            pumpSerial: UInt32?,
            origin: Origin,
            raw: Data,
            eventDate: Date,
            automatic: Bool,
            isFinalized: Bool
        ) {
            self.bolusId = bolusId
            self.pumpSerial = pumpSerial
            self.origin = origin
            self.raw = raw
            self.eventDate = eventDate
            self.automatic = automatic
            self.isFinalized = isFinalized
        }
    }

    public static let reportingHorizon: TimeInterval = .hours(24)
    /// Past the horizon: history dates an app bolus at activation on the pump's clock, which can be
    /// after its entry, and one pruned too soon is reported again as a pump-UI bolus.
    public static let retention: TimeInterval = reportingHorizon + .hours(12)

    /// When this build started recording commanded boluses.
    public let trackingSince: Date

    public private(set) var entries: [Entry]

    public init(trackingSince: Date, entries: [Entry] = []) {
        self.trackingSince = trackingSince
        self.entries = entries
    }

    /// An entry recorded before the serial was known matches any serial.
    public func entry(bolusId: Int, pumpSerial: UInt32) -> Entry? {
        entries.last { $0.bolusId == bolusId && ($0.pumpSerial == nil || $0.pumpSerial == pumpSerial) }
    }

    public mutating func record(_ entry: Entry) {
        entries.removeAll { $0.bolusId == entry.bolusId && $0.pumpSerial == entry.pumpSerial }
        entries.append(entry)
    }

    public mutating func markFinalized(raw: Data) {
        guard let index = entries.lastIndex(where: { $0.raw == raw }) else {
            return
        }
        entries[index].isFinalized = true
    }

    public mutating func prune(now: Date) {
        entries.removeAll { now.timeIntervalSince($0.eventDate) > Self.retention }
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
        self.init(trackingSince: Date(timeIntervalSinceReferenceDate: trackingSince), entries: entries)
    }

    public var rawValue: RawValue {
        [
            "trackingSince": trackingSince.timeIntervalSinceReferenceDate,
            "entries": entries.map(\.rawValue)
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
            raw: raw,
            eventDate: Date(timeIntervalSinceReferenceDate: eventDate),
            automatic: rawValue["automatic"] as? Bool ?? false,
            isFinalized: rawValue["isFinalized"] as? Bool ?? false
        )
    }

    public var rawValue: RawValue {
        var raw: RawValue = [
            "bolusId": bolusId,
            "origin": origin.rawValue,
            "raw": self.raw,
            "eventDate": eventDate.timeIntervalSinceReferenceDate,
            "automatic": automatic,
            "isFinalized": isFinalized
        ]
        raw["pumpSerial"] = pumpSerial
        return raw
    }
}
