import Foundation

public struct TandemPumpManagerSettings: RawRepresentable, Equatable {
    public typealias RawValue = [String: Any]

    public var maxBolus: Double?
    public var maxTempBasalRate: Double?
    public var maxBasalScheduleEntry: Double?

    public init(
        maxBolus: Double? = nil,
        maxTempBasalRate: Double? = nil,
        maxBasalScheduleEntry: Double? = nil
    ) {
        self.maxBolus = maxBolus
        self.maxTempBasalRate = maxTempBasalRate
        self.maxBasalScheduleEntry = maxBasalScheduleEntry
    }

    public init?(rawValue: RawValue) {
        func double(from value: Any?) -> Double? {
            switch value {
            case let doubleValue as Double:
                return doubleValue
            case let number as NSNumber:
                return number.doubleValue
            default:
                return nil
            }
        }

        maxBolus = double(from: rawValue["maxBolus"])
        maxTempBasalRate = double(from: rawValue["maxTempBasalRate"])
        maxBasalScheduleEntry = double(from: rawValue["maxBasalScheduleEntry"])
    }

    public var rawValue: RawValue {
        var raw: RawValue = [:]

        if let maxBolus = maxBolus {
            raw["maxBolus"] = maxBolus
        }

        if let maxTempBasalRate = maxTempBasalRate {
            raw["maxTempBasalRate"] = maxTempBasalRate
        }

        if let maxBasalScheduleEntry = maxBasalScheduleEntry {
            raw["maxBasalScheduleEntry"] = maxBasalScheduleEntry
        }

        return raw
    }
}

public extension TandemPumpManagerSettings {
    static let `default` = TandemPumpManagerSettings()
}

public enum TandemPumpManagerValidationError: LocalizedError, Equatable {
    case invalidBolusAmount(requested: Double)
    case maximumBolusExceeded(requested: Double, maximum: Double)
    case controlIQModeActive
    case bolusIsRunning

    public var errorDescription: String? {
        switch self {
        case let .invalidBolusAmount(requested):
            return String(
                format: String(
                    localized: "Cannot deliver a bolus of %.2f units",
                    comment: "Error when a bolus of zero or negative units is requested"
                ),
                requested
            )
        case let .maximumBolusExceeded(requested, maximum):
            return String(
                format: String(
                    localized: "Bolus of %.2f units exceeds the maximum bolus of %.2f units",
                    comment: "Error when a bolus is larger than the configured maximum bolus"
                ),
                requested,
                maximum
            )
        case .controlIQModeActive:
            // This is the reason the host app's loop is not dosing, and for most surfaces it is
            // the only text the user sees -- Trio, for one, prefixes it with a generic "could not
            // communicate with the pump". So it has to name the cause on its own rather than read
            // as one more communication failure.
            return String(
                localized: "Control-IQ is on: the pump is automating insulin delivery, so closed-loop dosing is paused",
                comment: "Error when a command is blocked because the pump is running Control-IQ"
            )
        case .bolusIsRunning:
            return String(
                localized: "A bolus is still being delivered",
                comment: "Error when a command is blocked because a bolus is in progress"
            )
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .invalidBolusAmount,
             .maximumBolusExceeded:
            return String(
                localized: "Check your maximum bolus in delivery limits, then try again.",
                comment: "Recovery suggestion when a bolus fails validation"
            )
        case .controlIQModeActive:
            return String(
                localized: "Turn Control-IQ off from this app's pump settings screen, or on the pump itself, to resume closed-loop dosing.",
                comment: "Recovery suggestion when Control-IQ blocks a command"
            )
        case .bolusIsRunning:
            return String(
                localized: "Wait for the bolus to finish, then try again.",
                comment: "Recovery suggestion when a bolus is in progress"
            )
        }
    }
}
