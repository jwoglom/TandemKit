import Foundation

/// The choices on TandemKit's temp basal screen, kept out of SwiftUI so Linux tests cover them. The
/// percent is the one value both the percent and the unit views edit.
public enum ManualTempBasalForm {
    public static let defaultPercent = 100
    public static let defaultDuration: TimeInterval = .minutes(30)
    public static let hourChoices = Array(0 ... 72)
    /// The pump takes any whole minute; a 5-minute step is quicker to set.
    public static let minuteChoices = Array(stride(from: 0, through: 55, by: 5))
    private static let step = 10

    /// `accepted` is `TandemPumpManager.manualTempBasalPercents` for the duration.
    public static func isValid(_ percent: Int, accepted: ClosedRange<Int>?) -> Bool {
        percent == 0 || accepted?.contains(percent) == true
    }

    public static func duration(hours: Int, minutes: Int) -> TimeInterval {
        .minutes(Double(hours * 60 + minutes))
    }

    public static func isValid(duration: TimeInterval) -> Bool {
        TandemPumpManager.supportedTempBasalMinutes.contains(Int(duration.minutes.rounded(.down)))
    }

    public static func canSet(_ percent: Int, accepted: ClosedRange<Int>?, duration: TimeInterval) -> Bool {
        isValid(percent, accepted: accepted) && isValid(duration: duration)
    }

    /// The next multiple of 10 up, raised to the lowest percent the pump takes; nil at the top.
    public static func stepUp(from percent: Int, accepted: ClosedRange<Int>?) -> Int? {
        guard let accepted, percent < accepted.upperBound else { return nil }
        let next = (max(percent, 0) / step + 1) * step
        return min(max(next, accepted.lowerBound), accepted.upperBound)
    }

    /// The next multiple of 10 down, never past the lowest percent the pump takes in one step: from
    /// there, 0. Nil at 0.
    public static func stepDown(from percent: Int, accepted: ClosedRange<Int>?) -> Int? {
        guard percent > 0 else { return nil }
        guard let accepted else { return 0 }
        let previous = min((percent - 1) / step * step, accepted.upperBound)
        if previous >= accepted.lowerBound {
            return previous
        }
        return percent > accepted.lowerBound ? accepted.lowerBound : 0
    }

    /// On the pump's 0.01 U/hr grid, as the driver reports the temp.
    public static func rate(percent: Int, profileBasalRate: Double) -> Double {
        TandemPumpCapabilities.roundToSupportedBasalRate(profileBasalRate * Double(percent) / 100)
    }

    /// The unit view's typed rate as the whole percent nearest it; nil without a profile rate.
    public static func percent(forRate unitsPerHour: Double, profileBasalRate: Double) -> Int? {
        guard profileBasalRate > 0, unitsPerHour >= 0, unitsPerHour.isFinite else { return nil }
        return Int((unitsPerHour / profileBasalRate * 100).rounded())
    }
}
