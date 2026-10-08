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
    case basalScheduleNotSynced
    case failedUpdatePumpProfile
    case pumpProfileBasalRateIsZero
    case tempBasalRateMismatch(expected: Double, actual: Double)

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
            return String(
                localized: "Control-IQ is active on the pump",
                comment: "Error when a command is blocked because the pump is running Control-IQ"
            )
        case .bolusIsRunning:
            return String(
                localized: "A bolus is still being delivered",
                comment: "Error when a command is blocked because a bolus is in progress"
            )
        case .basalScheduleNotSynced:
            return String(
                localized: "The pump's basal rates are not confirmed to match the app's",
                comment: "Error when a temp basal is blocked because the basal schedule has not been synced to the pump, or the pump's rate stopped matching it"
            )
        case .failedUpdatePumpProfile:
            return String(
                localized: "Failed to update pump basal profile",
                comment: "Error when a temp basal is blocked because the driver could not write the app's basal schedule to the pump"
            )
        case .pumpProfileBasalRateIsZero:
            return String(
                localized: "The pump's basal rate is 0 U/hr",
                comment: "Error when a temp basal is blocked because the pump's active profile has a basal rate of zero"
            )
        case let .tempBasalRateMismatch(expected, actual):
            return String(
                format: String(
                    localized: "The pump ran a temporary basal rate of %.2f U/hr instead of %.2f U/hr",
                    comment: "Error when the pump reads back a different temp basal rate than the one commanded"
                ),
                actual,
                expected
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
                localized: "Turn off Control-IQ on the pump to let this app control delivery.",
                comment: "Recovery suggestion when Control-IQ blocks a command"
            )
        case .bolusIsRunning:
            return String(
                localized: "Wait for the bolus to finish, then try again.",
                comment: "Recovery suggestion when a bolus is in progress"
            )
        case .basalScheduleNotSynced:
            return String(
                localized: "The pump's basal rates are being updated to match. Temporary basal rates start once the pump has them.",
                comment: "Recovery suggestion when a temp basal is blocked because the basal schedule has not been synced to the pump"
            )
        case .failedUpdatePumpProfile:
            let appName = HostApp.current.settingsName
            return String(
                format: String(
                    localized: "Could not update the pump's basal rates to match your current %1$@ configuration. Check your %2$@ defined basal rates. Until this is resolved you will be in open loop.",
                    comment: "Explanation when the driver could not write the app's basal schedule to the pump (1: app name, 2: app name)"
                ),
                appName,
                appName
            )
        case .pumpProfileBasalRateIsZero:
            return String(
                localized: "A temporary basal rate is a percentage of the pump's basal rate, so it would deliver no insulin. Check the active profile on the pump, or save your basal rates in the app's settings.",
                comment: "Recovery suggestion when a temp basal is blocked because the pump's active profile has a basal rate of zero"
            )
        case .tempBasalRateMismatch:
            return String(
                localized: "A temporary basal rate is a percentage of the pump's basal rate. Check that the pump's active profile matches the basal rates in the app's settings.",
                comment: "Recovery suggestion when the pump reads back a different temp basal rate than the one commanded"
            )
        }
    }
}
