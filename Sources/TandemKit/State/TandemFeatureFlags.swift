import Foundation

/// Opt-in switches for driver features that are not ready to be on for everyone.
///
/// A feature flag decides whether the app *offers* something; it never describes what the pump is
/// doing. Everything that keeps the driver honest about the pump's actual behaviour stays outside
/// the flags and runs unconditionally — the Control-IQ dosing guards in `TandemPumpManager`, and
/// the state sync that flips `useControlIQ` on when the pump reports Control-IQ enabled, are not
/// gated by `controlIQSupport`. Turning a flag off hides an affordance, it does not make the pump
/// forget it is running Control-IQ.
///
/// Stored inside `TandemPumpManagerState`, so a flag survives app restarts and is visible in the
/// state dump attached to a bug report.
public struct TandemFeatureFlags: RawRepresentable, Equatable {
    public typealias RawValue = [String: Any]

    public enum Flag: String, CaseIterable, Identifiable, Hashable {
        /// Surfaces the pump's Control-IQ settings screen and lets the user hand dosing over to
        /// Control-IQ from the pump settings screen.
        ///
        /// Off by default: handing dosing to Control-IQ turns the host app's closed loop off, and
        /// the flow is still being validated against hardware. It stays hidden until someone opts
        /// in from Debug Options.
        case controlIQSupport

        public var id: String { rawValue }

        /// Value used when the user has never touched this flag. Changing a default here moves
        /// everyone who has not made an explicit choice, which is the point: a flag graduating to
        /// on-by-default is a one-line change.
        public var defaultValue: Bool {
            switch self {
            case .controlIQSupport:
                return false
            }
        }

        public var title: String {
            switch self {
            case .controlIQSupport:
                return String(
                    localized: "Control-IQ Support",
                    comment: "Title of the Control-IQ support feature flag"
                )
            }
        }

        public var flagDescription: String {
            switch self {
            case .controlIQSupport:
                return String(
                    localized: "Shows Control-IQ Settings and allows switching the pump's algorithm to Control-IQ. Switching to Control-IQ turns off this app's closed loop.",
                    comment: "Description of the Control-IQ support feature flag"
                )
            }
        }
    }

    /// Explicit user choices only. A flag that is absent follows `Flag.defaultValue`.
    private var overrides: [Flag: Bool]

    /// Flags written by a newer build that this one does not know about. Carried through the raw
    /// value so downgrading and upgrading again does not silently discard a choice.
    private var unrecognized: [String: Bool]

    public init(overrides: [Flag: Bool] = [:]) {
        self.overrides = overrides
        unrecognized = [:]
    }

    public subscript(flag: Flag) -> Bool {
        get { overrides[flag] ?? flag.defaultValue }
        set { overrides[flag] = newValue }
    }

    /// Whether the user has made an explicit choice about `flag`, as opposed to inheriting the
    /// default. Used by the debug UI to label a row as customised.
    public func isOverridden(_ flag: Flag) -> Bool {
        overrides[flag] != nil
    }

    /// Drops the explicit choice, returning the flag to `Flag.defaultValue`.
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

    /// Convenience accessor for the flag that gates the Control-IQ surfaces.
    var controlIQSupport: Bool {
        self[.controlIQSupport]
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
