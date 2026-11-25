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
    case pumpClockUntrusted
    case tempBasalRateMismatch(expected: Double, actual: Double)
    case unsupportedTempBasalDuration(minutes: Int)
    /// Under Control-IQ: the pump took a temp at `sent` but reports one at `running`, or none.
    case tempRateReadbackMismatch(sent: Int, running: Int?)
    /// `accepted` is the non-zero percents the pump takes over the whole duration; nil for none.
    case manualTempBasalOutOfRange(percent: Int, accepted: ClosedRange<Int>?)
    case tempBasalAlreadyRunning
    case pumpIsSuspended

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
        case .pumpClockUntrusted:
            return String(
                localized: "The pump's clock is more than a day different from the phone's",
                comment: "Error when a bolus or temp basal is blocked because the pump's clock is more than a day off the phone's"
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
        case let .unsupportedTempBasalDuration(minutes):
            return String(
                format: String(
                    localized: "The pump cannot run a temporary basal rate for %d minutes",
                    comment: "Error when a temp basal is requested for a duration the pump does not accept (minutes)"
                ),
                minutes
            )
        case let .tempRateReadbackMismatch(sent, running?):
            return String(
                format: String(
                    localized: "The pump runs a temporary basal rate of %1$d%% instead of %2$d%%",
                    comment: "Error when the pump took a temp basal set from TandemKit's settings but reports another (1: the percent it runs, 2: the percent sent)"
                ),
                running,
                sent
            )
        case let .tempRateReadbackMismatch(sent, nil):
            return String(
                format: String(
                    localized: "The pump took a temporary basal rate of %d%% but does not run it",
                    comment: "Error when the pump took a temp basal set from TandemKit's settings but reports none running (the percent sent)"
                ),
                sent
            )
        case let .manualTempBasalOutOfRange(percent, _):
            return String(
                format: String(
                    localized: "The pump cannot run a temporary basal rate of %d%%",
                    comment: "Error when a temp basal set from TandemKit's settings is outside what the pump accepts (percent of the profile)"
                ),
                percent
            )
        case .tempBasalAlreadyRunning:
            return String(
                localized: "Another temporary basal rate is running",
                comment: "Error when a temp basal set from TandemKit's settings finds another temp running on the pump"
            )
        case .pumpIsSuspended:
            return String(
                localized: "Insulin delivery is suspended on the pump",
                comment: "Error when a temp basal is blocked because the pump is suspended"
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
        case .pumpClockUntrusted:
            return String(
                localized: "Boluses and temporary basal rates from the app are paused until the pump's time is set. Open the pump's settings in the app and sync its time.",
                comment: "Recovery suggestion when a bolus or temp basal is blocked because the pump's clock is more than a day off the phone's"
            )
        case .tempBasalRateMismatch:
            return String(
                localized: "A temporary basal rate is a percentage of the pump's basal rate. Check that the pump's active profile matches the basal rates in the app's settings.",
                comment: "Recovery suggestion when the pump reads back a different temp basal rate than the one commanded"
            )
        case .unsupportedTempBasalDuration:
            return String(
                localized: "The pump runs a temporary basal rate for 15 minutes to 72 hours. Choose a duration in that range.",
                comment: "Recovery suggestion when a temp basal is requested for a duration the pump does not accept"
            )
        case .tempRateReadbackMismatch:
            return String(
                localized: "Check the temporary basal rate on the pump's screen.",
                comment: "Recovery suggestion when the pump reports another temp basal than the one it took from TandemKit's settings"
            )
        case let .manualTempBasalOutOfRange(_, accepted):
            guard let accepted else {
                return String(
                    format: String(
                        localized: "Over this duration the pump can only run %d%% of its basal rate.",
                        comment: "Recovery suggestion when no non-zero temp basal fits the pump's limits over the chosen duration (the percent, 0)"
                    ),
                    0
                )
            }
            return String(
                format: String(
                    localized: "Over this duration the pump runs 0%% or %1$d%% to %2$d%% of its basal rate.",
                    comment: "Recovery suggestion when a temp basal is outside the pump's limits (1: lowest percent, 2: highest percent)"
                ),
                accepted.lowerBound,
                accepted.upperBound
            )
        case .tempBasalAlreadyRunning:
            return String(
                localized: "Stop the temporary basal rate that is running, or wait for it to end.",
                comment: "Recovery suggestion when a temp basal set from TandemKit's settings finds another temp running"
            )
        case .pumpIsSuspended:
            return String(
                localized: "No temporary basal rate was set. Resume insulin delivery to let the app control basal again.",
                comment: "Recovery suggestion when a temp basal is blocked because the pump is suspended"
            )
        }
    }
}
