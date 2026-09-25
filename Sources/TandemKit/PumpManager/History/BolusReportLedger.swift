import Foundation

/// What this driver has told the host app about each recent bolus, keyed by the pump's `bolusId`.
///
/// The live path reports a bolus the app commands under a `raw` built from its programmed amount
/// and the moment it was programmed (`NewPumpEvent.bolus`); history identifies the same bolus by
/// `bolusId` (`HistoryLogSyncIdentifier.bolus`). The two can never be matched after the fact, and
/// both hosts dedupe on `raw`, so reporting a history bolus without knowing it was already
/// reported live counts it twice (#344, #105). This ledger is that knowledge: an entry is written
/// the moment `InitiateBolus` succeeds, and history reporting consults it before emitting.
///
/// Persisted, unlike the session history store: a bolus commanded before a relaunch shows up in
/// the first history read after it.
public struct BolusReportLedger: Equatable {
    public enum Origin: String, Equatable {
        /// Commanded by this app; `raw` and `eventDate` are what the live path reported.
        case commanded
        /// Found only in the pump's history log (pump UI, Control-IQ, a lost acknowledgement).
        case history
    }

    public struct Entry: Equatable {
        public let bolusId: Int
        public let pumpSerial: UInt32?
        public let origin: Origin
        /// The identity every report of this bolus must carry.
        public let raw: Data
        /// The `NewPumpEvent.date` every report of this bolus must carry: Trio stores it as the
        /// row's timestamp and falls back to it for dedupe.
        public let eventDate: Date
        public let automatic: Bool
        /// Whether an immutable dose has been reported. The host never revises a finalized row,
        /// so nothing more is sent once this is set.
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

    /// How long an entry is kept. History reporting never looks further back than this, and a
    /// `bolusId` (a 16-bit counter) cannot come round again within it.
    public static let retention: TimeInterval = .hours(24)

    /// When this build started recording commanded boluses. A bolus older than this cannot be
    /// told apart from one an earlier build commanded and reported live without an entry, so
    /// history reporting must not reach below it — doing so would double every recent app bolus
    /// the moment reporting is turned on.
    public let trackingSince: Date

    public private(set) var entries: [Entry]

    public init(trackingSince: Date, entries: [Entry] = []) {
        self.trackingSince = trackingSince
        self.entries = entries
    }

    /// The entry for `bolusId` on this pump. An entry recorded before the serial was known
    /// matches any serial: the live path can command a bolus before `PumpVersionResponse` lands.
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
