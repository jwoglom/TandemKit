import Foundation

/// Bounds the pump applies to the body weight and total daily insulin that
/// Control-IQ needs in order to run.
///
/// Control-IQ cannot be enabled until both values are present on the pump: the
/// algorithm uses them to derive its dosing constraints. A pump that has never
/// had them entered reports zero for both, and rejects any
/// `ChangeControlIQSettingsRequest` that would enable Control-IQ with values it
/// considers implausible.
///
/// The minimums below are Tandem's documented Control-IQ requirements. The
/// maximums are *not* authoritative — they are wide sanity bounds that keep an
/// obvious typo from reaching the pump. The pump remains the final authority on
/// what it will accept, and its rejection is surfaced to the caller rather than
/// being second-guessed here.
public enum ControlIQSettingsLimits {
    public static let minimumWeightPounds = 55
    public static let minimumWeightKilograms = 25
    public static let maximumWeightPounds = 400
    public static let maximumWeightKilograms = 181

    public static let minimumTotalDailyInsulinUnits = 10
    public static let maximumTotalDailyInsulinUnits = 200

    /// Inclusive weight range for `unit`.
    public static func weightRange(for unit: ControlIQWeightUnit) -> ClosedRange<Int> {
        switch unit {
        case .pounds:
            return minimumWeightPounds ... maximumWeightPounds
        case .kilograms:
            return minimumWeightKilograms ... maximumWeightKilograms
        }
    }

    /// Inclusive total daily insulin range, in whole units.
    public static var totalDailyInsulinRange: ClosedRange<Int> {
        minimumTotalDailyInsulinUnits ... maximumTotalDailyInsulinUnits
    }

    /// Validates the values that would be sent in a `ChangeControlIQSettingsRequest`.
    ///
    /// Only checked when `enabled` is true: the pump does not need plausible
    /// values to turn Control-IQ off, and blocking a disable request on a
    /// validation failure would leave a user unable to get back out of
    /// Control-IQ from the app.
    ///
    /// - Parameters:
    ///   - enabled: Whether the request would enable Control-IQ.
    ///   - weight: Body weight, expressed in `weightUnit`. `nil` means the value
    ///     has never been configured on the pump.
    ///   - weightUnit: Unit `weight` is expressed in.
    ///   - totalDailyInsulin: Total daily insulin in whole units. `nil` means the
    ///     value has never been configured on the pump.
    public static func validate(
        enabled: Bool,
        weight: Int?,
        weightUnit: ControlIQWeightUnit,
        totalDailyInsulin: Int?
    ) throws {
        guard enabled else { return }

        guard let weight, weight > 0 else {
            throw ControlIQSettingsError.weightNotConfigured
        }

        guard let totalDailyInsulin, totalDailyInsulin > 0 else {
            throw ControlIQSettingsError.totalDailyInsulinNotConfigured
        }

        let allowedWeight = weightRange(for: weightUnit)
        guard allowedWeight.contains(weight) else {
            throw ControlIQSettingsError.weightOutOfRange(
                weight: weight,
                unit: weightUnit,
                allowed: allowedWeight
            )
        }

        guard totalDailyInsulinRange.contains(totalDailyInsulin) else {
            throw ControlIQSettingsError.totalDailyInsulinOutOfRange(
                units: totalDailyInsulin,
                allowed: totalDailyInsulinRange
            )
        }
    }
}

/// Why a Control-IQ settings change could not be applied — either because we
/// refused to send it, or because the pump refused it.
public enum ControlIQSettingsError: LocalizedError, Equatable {
    /// The pump has no body weight stored, so Control-IQ cannot be enabled.
    case weightNotConfigured
    /// The pump has no total daily insulin stored, so Control-IQ cannot be enabled.
    case totalDailyInsulinNotConfigured
    case weightOutOfRange(weight: Int, unit: ControlIQWeightUnit, allowed: ClosedRange<Int>)
    case totalDailyInsulinOutOfRange(units: Int, allowed: ClosedRange<Int>)
    /// The pump answered with a non-zero status. Codes are not catalogued, so the
    /// raw value is reported as-is.
    case rejectedByPump(status: Int)
    /// The pump reported a weight unit we do not recognise. Writing the weight back
    /// would risk changing it, so the change is refused instead.
    case unknownWeightUnit(raw: Int)

    public var errorDescription: String? {
        switch self {
        case let .rejectedByPump(status):
            return String(
                format: String(
                    localized: "The pump rejected the Control-IQ change (status %d). Control-IQ needs a body weight and total daily insulin set on the pump before it can be turned on.",
                    comment: "Error shown when the pump refuses a Control-IQ settings change"
                ),
                status
            )
        case let .unknownWeightUnit(raw):
            return String(
                format: String(
                    localized: "The pump reported an unrecognized weight unit (%d). Check the Control-IQ settings on the pump.",
                    comment: "Error shown when the pump's Control-IQ weight unit cannot be decoded"
                ),
                raw
            )
        case .weightNotConfigured:
            return String(
                localized: "Control-IQ needs a body weight. Enter one below before turning Control-IQ on.",
                comment: "Error shown when enabling Control-IQ without a weight configured"
            )
        case .totalDailyInsulinNotConfigured:
            return String(
                localized: "Control-IQ needs a total daily insulin amount. Enter one below before turning Control-IQ on.",
                comment: "Error shown when enabling Control-IQ without a total daily insulin configured"
            )
        case let .weightOutOfRange(weight, unit, allowed):
            let unitLabel = unit == .pounds
                ? String(localized: "lbs", comment: "Abbreviation for pounds")
                : String(localized: "kg", comment: "Abbreviation for kilograms")
            return String(
                format: String(
                    localized: "Weight of %1$d %2$@ is outside the range Control-IQ accepts (%3$d–%4$d %2$@).",
                    comment: "Error shown when the Control-IQ weight is out of range"
                ),
                weight,
                unitLabel,
                allowed.lowerBound,
                allowed.upperBound
            )
        case let .totalDailyInsulinOutOfRange(units, allowed):
            return String(
                format: String(
                    localized: "Total daily insulin of %1$d U is outside the range Control-IQ accepts (%2$d–%3$d U).",
                    comment: "Error shown when the Control-IQ total daily insulin is out of range"
                ),
                units,
                allowed.lowerBound,
                allowed.upperBound
            )
        }
    }
}
