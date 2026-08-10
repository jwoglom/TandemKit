import Foundation

/// Bounds on the weight and total-daily-insulin values that can be sent to the pump when enabling
/// Control-IQ, and the kilogram/pound conversion used to normalize what the pump reports.
///
/// A pump on which Control-IQ has never been configured reports a weight and TDI of zero, and it
/// rejects a `ChangeControlIQSettingsRequest` carrying those zeroes with a non-OK status -- which
/// is what made enabling Control-IQ from the app fail until the values had been set in the Tandem
/// app (jwoglom/TandemKit#223). These bounds let the driver refuse such a request before it goes
/// out, so the failure names the missing value instead of surfacing a bare "check pump connection".
///
/// The pump is the real authority on what it accepts; these are the app-side floors below which a
/// request is known to be pointless. The upper bounds are what the wire format can carry: two bytes
/// for the weight, one for the TDI.
public enum ControlIQSettingsLimits {
    /// Any nonzero weight is allowed. Zero means "never configured", not "weighs nothing".
    public static let allowedWeightLbs = 1 ... 0xFFFF

    /// Control-IQ requires at least 10 U/day.
    public static let allowedTotalDailyInsulinUnits = 10 ... 0xFF

    /// Why a weight/TDI pair cannot be sent to the pump.
    public enum ValidationFailure: Equatable {
        case weightOutOfRange(lbs: Int)
        case totalDailyInsulinOutOfRange(units: Int)
    }

    /// Returns the reason `weightLbs`/`totalDailyInsulinUnits` cannot be sent, or nil when the pair
    /// is within range. Only meaningful when enabling Control-IQ: disabling it does not depend on
    /// either value.
    public static func validate(weightLbs: Int, totalDailyInsulinUnits: Int) -> ValidationFailure? {
        if !allowedWeightLbs.contains(weightLbs) {
            return .weightOutOfRange(lbs: weightLbs)
        }
        if !allowedTotalDailyInsulinUnits.contains(totalDailyInsulinUnits) {
            return .totalDailyInsulinOutOfRange(units: totalDailyInsulinUnits)
        }
        return nil
    }

    /// Converts a weight the pump reported in `unit` into the pounds that
    /// `ChangeControlIQSettingsRequest` carries on the wire.
    ///
    /// The request always declares pounds (cargo byte 3 is a fixed 1), so a pump configured in
    /// kilograms has to be converted before its own reading can be echoed back -- otherwise a
    /// 70 kg weight round-trips as 70 lb.
    public static func pounds(from weight: Int, unit: ControlIQInfoAbstractResponse.WeightUnit?) -> Int {
        switch unit {
        case .kilograms:
            return Int((Double(weight) * 2.2046226218).rounded())
        case .pounds,
             nil:
            return weight
        }
    }
}
