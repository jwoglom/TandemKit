import Foundation

/// Why a Control-IQ configuration change could not be applied.
///
/// `TandemPumpManager.configureControlIQMode` validates the request before writing it, so the
/// caller can tell "the pump has no weight/TDI configured yet" apart from "the pump did not
/// answer" -- a distinction the UI previously collapsed into a single "check pump connection"
/// message (jwoglom/TandemKit#223).
public enum ControlIQConfigurationError: Error, Equatable {
    /// Control-IQ has never been configured on this pump, so there is no weight to send.
    case weightNotSet
    /// Control-IQ has never been configured on this pump, so there is no TDI to send.
    case totalDailyInsulinNotSet
    case weightOutOfRange(lbs: Int)
    case totalDailyInsulinOutOfRange(units: Int)
    /// The pump answered, and rejected the change with this status code.
    case pumpRejected(status: Int)
    /// The request went out and nothing came back. Connection failures surface as the underlying
    /// `PumpCommError` instead, so they keep their own diagnosis.
    case noResponse

    init(_ failure: ControlIQSettingsLimits.ValidationFailure) {
        switch failure {
        case let .weightOutOfRange(lbs):
            self = lbs == 0 ? .weightNotSet : .weightOutOfRange(lbs: lbs)
        case let .totalDailyInsulinOutOfRange(units):
            self = units == 0 ? .totalDailyInsulinNotSet : .totalDailyInsulinOutOfRange(units: units)
        }
    }
}

/// What stands in the way of switching to Control-IQ, found before anything is sent to the pump.
enum ControlIQEnableBlocker: Equatable {
    /// No weight or total daily insulin to send; the driver refuses the enable without them (#223).
    case valuesRequired
    /// No CGM sensor session on the pump, so Control-IQ would run open-loop with the app's own algorithm off.
    case cgmRequired
}

extension ControlIQConfigurationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .weightNotSet:
            return String(
                localized: "Control-IQ needs your weight before it can be turned on.",
                comment: "Error when enabling Control-IQ without a weight configured"
            )
        case .totalDailyInsulinNotSet:
            return String(
                localized: "Control-IQ needs your total daily insulin before it can be turned on.",
                comment: "Error when enabling Control-IQ without a total daily insulin configured"
            )
        case let .weightOutOfRange(lbs):
            return String(
                format: String(
                    localized: "%@ lbs is not a weight the pump will accept for Control-IQ.",
                    comment: "Error when the Control-IQ weight is outside the accepted range"
                ),
                String(lbs)
            )
        case let .totalDailyInsulinOutOfRange(units):
            return String(
                format: String(
                    localized: "Control-IQ requires a total daily insulin of at least %@ units; %@ was entered.",
                    comment: "Error when the Control-IQ total daily insulin is outside the accepted range"
                ),
                String(ControlIQSettingsLimits.allowedTotalDailyInsulinUnits.lowerBound),
                String(units)
            )
        case let .pumpRejected(status):
            return String(
                format: String(
                    localized: "The pump rejected the Control-IQ settings (status %@).",
                    comment: "Error when the pump returns a non-OK status for a Control-IQ change"
                ),
                String(status)
            )
        case .noResponse:
            return PumpCommError.noResponse.errorDescription
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .totalDailyInsulinNotSet,
             .totalDailyInsulinOutOfRange,
             .weightNotSet,
             .weightOutOfRange:
            return String(
                localized: "Enter your weight and total daily insulin in Control-IQ Settings, then try again.",
                comment: "Recovery suggestion when Control-IQ weight/TDI are missing or out of range"
            )
        case .pumpRejected:
            return String(
                localized: "Review the values and try again.",
                comment: "Recovery suggestion when the pump rejects a Control-IQ change"
            )
        case .noResponse:
            return PumpCommError.noResponse.recoverySuggestion
        }
    }
}

public enum SleepScheduleWriteError: Error, Equatable {
    case unsupported
    case pumpRejected(status: Int)
    case noResponse
    /// The pump answered OK, but reading the schedules back shows the slot unchanged or different.
    case notApplied
}

extension SleepScheduleWriteError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupported:
            return String(
                localized: "This pump does not accept sleep schedule changes from the app.",
                comment: "Error when the pump cannot accept a sleep schedule write"
            )
        case let .pumpRejected(status):
            return String(
                format: String(
                    localized: "The pump rejected the sleep schedule (status %@).",
                    comment: "Error when the pump returns a non-OK status for a sleep schedule change"
                ),
                String(status)
            )
        case .noResponse:
            return PumpCommError.noResponse.errorDescription
        case .notApplied:
            return String(
                localized: "The pump accepted the sleep schedule but did not save it.",
                comment: "Error when a sleep schedule reads back from the pump unchanged after a write"
            )
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .unsupported:
            return String(
                localized: "Change sleep schedules on the pump itself, or in the Tandem app.",
                comment: "Recovery suggestion when the pump cannot accept a sleep schedule write"
            )
        case .notApplied,
             .pumpRejected:
            return String(
                localized: "Check the schedule's days and times, then try again.",
                comment: "Recovery suggestion when the pump rejects or does not save a sleep schedule"
            )
        case .noResponse:
            return PumpCommError.noResponse.recoverySuggestion
        }
    }
}
