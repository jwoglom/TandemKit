import Foundation

/// Fixed hardware capabilities of the supported Tandem pumps, kept in TandemCore so both the pump
/// manager and dose bookkeeping share one definition on every platform.
public enum TandemPumpCapabilities {
    /// Tandem Mobi and t:slim X2: 0.0u, then 0.1 - 15.00u/hr in 0.01u chunks
    public static let supportedBasalRates: [Double] = {
        let multiplier = 1000.0
        let start = Int(round(0.1 * multiplier))
        let end = Int(round(15.0 * multiplier))
        let step = Int(round(0.01 * multiplier))
        return [0.0] + stride(from: start, through: end, by: step).map { Double($0) / multiplier }
    }()

    /// Round an insulin amount to the pump's native milliunit reporting resolution, stripping
    /// Float32 representation noise (e.g. `Float(0.9)` = 0.89999997) without distorting genuine
    /// partial deliveries (e.g. a cancelled bolus of 1.041 U). Round-to-**nearest** — NOT the
    /// floor-to-command-grid `roundToSupportedBolusVolume`, which combined with the Float
    /// undershoot could drop a whole increment and understate delivered IOB (the unsafe direction).
    public static func roundToReportingResolution(_ units: Double) -> Double {
        (units * 1000).rounded() / 1000
    }

    // MARK: - Bolus delivery timing

    // Larger deliveries are faster -- a 10.05u bolus is almost twice as fast as a 9.95u one.
    // Both rates are confirmed by pump logs: across three days of boluses, delivery took the
    // reported volume divided by the rate below to within a second and a half.

    /// Units per second, for deliveries under 10 U.
    public static let bolusSpeedUnder10U = 1 / 28.745858684009523
    /// Units per second, for deliveries of 10 U and over.
    public static let bolusSpeedOver10U = 1 / 11.200233479381131

    /// How long the pump spends accepting a bolus request before insulin starts moving. Exactly
    /// 15 s in every bolus across three days of pump logs.
    public static let bolusInitiationDelay: TimeInterval = 15

    /// How long the pump takes to deliver `units`, at its nominal delivery rate. Excludes
    /// `bolusInitiationDelay`.
    public static func estimatedBolusDuration(toDeliver units: Double) -> TimeInterval {
        if units < 10 {
            units / bolusSpeedUnder10U
        } else {
            units / bolusSpeedOver10U
        }
    }

    /// Units of a `units` bolus the pump delivers in `elapsed` seconds of delivery, at its
    /// nominal rate.
    public static func unitsDelivered(in elapsed: TimeInterval, ofBolus units: Double) -> Double {
        let rate = units < 10 ? bolusSpeedUnder10U : bolusSpeedOver10U
        return min(units, max(0, elapsed) * rate)
    }
}
