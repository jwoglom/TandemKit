import Foundation

/// Switches for driver features that are still being validated, persisted in
/// `TandemPumpManagerState`.
///
/// A flag decides what the app offers or enforces; it never describes what the pump is doing. The
/// Control-IQ dosing guards and the state sync that flips `useControlIQ` on when the pump reports
/// Control-IQ enabled are not gated by any flag.
public struct TandemFeatureFlags: RawRepresentable, Equatable {
    public typealias RawValue = [String: Any]

    public enum Flag: String, CaseIterable, Identifiable, Hashable {
        /// Surfaces the pump's Control-IQ settings screen and lets the user hand dosing over to
        /// Control-IQ.
        case controlIQSupport

        /// Allows the pump's quick bolus button to stay on. While off, every sync confirms the
        /// button is disabled on the pump and turns it off if it is not.
        case quickBolusButtonSupport

        /// Runs the history log backfill at all: the incremental read, gap healing and the walk
        /// backward. While off, `HistoryBackfillCoordinator` does nothing on any tick and the
        /// driver never reads the pump's history log.
        case historyBackfill

        /// Lets doses found in the pump's history log reach the app's insulin history. Only has
        /// any effect while `historyBackfill` is on — there is nothing to report otherwise.
        case historyDoseReporting

        /// Lets the basal the pump delivered, read from its history log, correct what the app was
        /// told. While off the comparison still runs, with `historyBackfill`, and only logs.
        case basalHistoryReporting

        /// Shows "Set temp basal" in the pump's settings, to set or stop a temp basal by hand.
        case manualTempBasalSupport

        public var id: String { rawValue }

        public var defaultValue: Bool {
            switch self {
            case .controlIQSupport,
                 .quickBolusButtonSupport,
                 .historyBackfill,
                 .historyDoseReporting,
                 .basalHistoryReporting,
                 .manualTempBasalSupport:
                return true
            }
        }

        public var title: String {
            switch self {
            case .controlIQSupport:
                return String(
                    localized: "Control-IQ Support",
                    comment: "Title of the Control-IQ support feature flag"
                )
            case .quickBolusButtonSupport:
                return String(
                    localized: "Quick Bolus Button Support",
                    comment: "Title of the quick bolus button support feature flag"
                )
            case .historyBackfill:
                return String(
                    localized: "History Backfill",
                    comment: "Title of the history backfill feature flag"
                )
            case .historyDoseReporting:
                return String(
                    localized: "History Dose Reporting",
                    comment: "Title of the history dose reporting feature flag"
                )
            case .basalHistoryReporting:
                return String(
                    localized: "History Basal Reporting",
                    comment: "Title of the history basal reporting feature flag"
                )
            case .manualTempBasalSupport:
                return String(
                    localized: "Manual Temp Basal Support",
                    comment: "Title of the manual temp basal support feature flag"
                )
            }
        }

        public var flagDescription: String {
            switch self {
            case .controlIQSupport:
                return String(
                    localized: "Shows Control-IQ Settings and Mobi CGM settings, and allows switching the pump's algorithm to Control-IQ. Switching to Control-IQ turns off this app's closed loop.",
                    comment: "Description of the Control-IQ support feature flag"
                )
            case .quickBolusButtonSupport:
                return String(
                    localized: "Allows the pump's quick bolus button to be used. While off, the app turns the quick bolus button off on the pump every time it syncs.",
                    comment: "Description of the quick bolus button support feature flag"
                )
            case .historyBackfill:
                return String(
                    localized: "Reads the pump's history log to catch up on insulin delivered while the app was not connected. While off, the app does not read pump history at all.",
                    comment: "Description of the history backfill feature flag"
                )
            case .historyDoseReporting:
                return String(
                    localized: "Adds boluses found in the pump's history log to the app's insulin history, so boluses delivered from the pump itself are counted. Needs History Backfill to be on. While off, pump history is read but never changes the app's insulin history.",
                    comment: "Description of the history dose reporting feature flag"
                )
            case .basalHistoryReporting:
                return String(
                    localized: "Checks the basal rates the pump delivered, from its history log, against what the app was told, and reports the difference to the app's insulin history: Control-IQ's basal changes, temp rates the app did not set or lost track of, and a pump profile that differs from the app's schedule. Only has any effect while History Backfill is on.",
                    comment: "Description of the history basal reporting feature flag"
                )
            case .manualTempBasalSupport:
                return String(
                    localized: "Shows Set temp basal in the pump's settings, to set a temporary basal rate by hand or stop the one running. While a temporary basal rate set there runs, this app's automatic dosing is paused.",
                    comment: "Description of the manual temp basal support feature flag"
                )
            }
        }
    }

    /// Explicit user choices only; an absent flag follows `Flag.defaultValue`.
    private var overrides: [Flag: Bool]

    /// Flags written by a newer build, carried through so a downgrade does not discard a choice.
    private var unrecognized: [String: Bool]

    public init(overrides: [Flag: Bool] = [:]) {
        self.overrides = overrides
        unrecognized = [:]
    }

    public subscript(flag: Flag) -> Bool {
        get { overrides[flag] ?? flag.defaultValue }
        set { overrides[flag] = newValue }
    }

    public func isOverridden(_ flag: Flag) -> Bool {
        overrides[flag] != nil
    }

    public mutating func clear(_ flag: Flag) {
        overrides.removeValue(forKey: flag)
    }

    public init?(rawValue: RawValue) {
        overrides = [:]
        unrecognized = [:]

        for (key, value) in rawValue {
            guard let enabled = TandemFeatureFlags.bool(from: value) else {
                continue
            }

            if let flag = Flag(rawValue: key) {
                overrides[flag] = enabled
            } else {
                unrecognized[key] = enabled
            }
        }
    }

    public var rawValue: RawValue {
        var raw: RawValue = unrecognized

        for (flag, enabled) in overrides {
            raw[flag.rawValue] = enabled
        }

        return raw
    }

    private static func bool(from value: Any) -> Bool? {
        switch value {
        case let boolValue as Bool:
            return boolValue
        case let number as NSNumber:
            return number.boolValue
        default:
            return nil
        }
    }
}

public extension TandemFeatureFlags {
    static let `default` = TandemFeatureFlags()

    var controlIQSupport: Bool {
        self[.controlIQSupport]
    }

    var quickBolusButtonSupport: Bool {
        self[.quickBolusButtonSupport]
    }

    var historyBackfill: Bool {
        self[.historyBackfill]
    }

    /// Gated on `historyBackfill` as well: there is nothing to report from a log never read.
    var historyDoseReporting: Bool {
        self[.historyBackfill] && self[.historyDoseReporting]
    }

    var basalHistoryReporting: Bool {
        self[.historyBackfill] && self[.basalHistoryReporting]
    }

    var manualTempBasalSupport: Bool {
        self[.manualTempBasalSupport]
    }
}

extension TandemFeatureFlags: CustomStringConvertible {
    public var description: String {
        let entries = Flag.allCases.map { flag in
            "\(flag.rawValue): \(self[flag])\(isOverridden(flag) ? "" : " (default)")"
        }
        return "[" + entries.joined(separator: ", ") + "]"
    }
}
