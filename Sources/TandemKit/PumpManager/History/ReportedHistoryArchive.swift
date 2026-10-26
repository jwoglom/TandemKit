import Foundation

/// What deleted managers told this app's host, by pump. The host drops a deleted manager's state but
/// keeps the doses it was given, and setup's history load in a later manager for the same pump reported
/// them again under history's identifiers. Kept in the host app's defaults, since nothing else of a
/// deleted manager outlives it.
public final class ReportedHistoryArchive {
    public struct Reported: Equatable {
        public var savedAt: Date
        public var boluses: [BolusReportLedger.Entry]
        public var basalRows: [ReportedBasalLedger.Row]
        public var transitions: [DeliveryTransitionLedger.Entry]

        public init(
            savedAt: Date,
            boluses: [BolusReportLedger.Entry] = [],
            basalRows: [ReportedBasalLedger.Row] = [],
            transitions: [DeliveryTransitionLedger.Entry] = []
        ) {
            self.savedAt = savedAt
            self.boluses = boluses
            self.basalRows = basalRows
            self.transitions = transitions
        }
    }

    public static let retention = ReportedBasalLedger.retention
    private static let key = "com.jwoglom.TandemKit.reportedHistoryArchive"

    private let defaults: UserDefaults?
    private let lock = NSLock()
    private var unsaved: [String: Any] = [:]

    /// Without `defaults` the archive lives as long as the object, as a test's does.
    public init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    public func reported(pumpSerial: UInt32, now: Date) -> Reported? {
        withLock {
            guard let reported = (stored[String(pumpSerial)] as? [String: Any]).flatMap(Reported.init(rawValue:)),
                  now.timeIntervalSince(reported.savedAt) <= Self.retention
            else {
                return nil
            }
            return reported
        }
    }

    public func save(_ reported: Reported, pumpSerial: UInt32) {
        withLock {
            var all = stored.filter { _, value in
                guard let saved = (value as? [String: Any]).flatMap(Reported.init(rawValue:)) else { return false }
                return reported.savedAt.timeIntervalSince(saved.savedAt) <= Self.retention
            }
            all[String(pumpSerial)] = reported.rawValue
            stored = all
        }
    }

    private var stored: [String: Any] {
        get { defaults.map { $0.dictionary(forKey: Self.key) ?? [:] } ?? unsaved }
        set {
            if let defaults {
                defaults.set(newValue, forKey: Self.key)
            } else {
                unsaved = newValue
            }
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

// MARK: - Raw representation

extension ReportedHistoryArchive.Reported: RawRepresentable {
    public typealias RawValue = [String: Any]

    public init?(rawValue: RawValue) {
        guard let savedAt = rawValue["savedAt"] as? TimeInterval else {
            return nil
        }
        self.init(
            savedAt: Date(timeIntervalSinceReferenceDate: savedAt),
            boluses: (rawValue["boluses"] as? [[String: Any]] ?? []).compactMap(BolusReportLedger.Entry.init(rawValue:)),
            basalRows: (rawValue["basalRows"] as? [[String: Any]] ?? []).compactMap(ReportedBasalLedger.Row.init(rawValue:)),
            transitions: (rawValue["transitions"] as? [[String: Any]] ?? []).compactMap(DeliveryTransitionLedger.Entry.init(rawValue:))
        )
    }

    public var rawValue: RawValue {
        [
            "savedAt": savedAt.timeIntervalSinceReferenceDate,
            "boluses": boluses.map(\.rawValue),
            "basalRows": basalRows.map(\.rawValue),
            "transitions": transitions.map(\.rawValue)
        ]
    }
}
