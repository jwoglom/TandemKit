import Foundation
import LoopKit

/// Where the host's max basal is above what the pump can run. A temp rate is a whole percent of
/// the pump's profile rate, at most `TandemPumpManager.maximumTempBasalPercent`, and LoopKit has no
/// way to tell the host of a cap that moves with the schedule, so a request above it is cut.
public struct TempBasalCeiling: Equatable {
    public struct CappedSegment: Equatable {
        /// Seconds from midnight, on the pump's clock.
        public let startTime: TimeInterval
        public let endTime: TimeInterval
        public let scheduledRate: Double
        /// The highest temp basal the pump runs in this segment, in U/hr.
        public let ceiling: Double
    }

    public static var maximumPercent: Int { TandemPumpManager.maximumTempBasalPercent }

    public let maxBasal: Double
    public let cappedSegments: [CappedSegment]

    /// Nil when the max basal fits under every segment, or the schedule is the all-zero placeholder.
    public init?(schedule: BasalRateSchedule, maxBasal: Double?) {
        guard let maxBasal, maxBasal > 0, schedule.items.contains(where: { $0.value > 0 }) else { return nil }

        let items = schedule.items
        let capped = items.enumerated().compactMap { index, item -> CappedSegment? in
            // A 0 U/hr segment runs no temp basal above zero: the driver refuses one.
            guard item.value == 0 || TandemPumpManager.tempBasalExceedsCeiling(requestedRate: maxBasal, baseline: item.value)
            else { return nil }
            return CappedSegment(
                startTime: item.startTime,
                endTime: index + 1 < items.count ? items[index + 1].startTime : .hours(24),
                scheduledRate: item.value,
                ceiling: item.value * Double(Self.maximumPercent) / 100
            )
        }
        guard !capped.isEmpty else { return nil }

        self.maxBasal = maxBasal
        cappedSegments = capped
    }
}

extension TandemPumpManager {
    public var tempBasalCeiling: TempBasalCeiling? {
        TempBasalCeiling(schedule: state.basalRateSchedule, maxBasal: state.settings.maxTempBasalRate)
    }
}
