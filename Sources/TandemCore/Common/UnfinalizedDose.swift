import Foundation
import LoopKit

public class UnfinalizedDose: Equatable {
    public typealias RawValue = [String: Any]

    private let logger = TandemLogger(category: "UnfinalizedDose")

    public var bolusId: Int?
    /// The pump's id for a temp rate the app set, from `SetTempRateResponse`.
    public var tempRateId: Int?
    /// The percent of the pump's profile a temp rate the app set runs at.
    public var tempPercent: Int?
    /// A temp basal's `raw` from the pump's `tempRateId`, minted when it started. See `tempBasalRaw`.
    public var eventRaw: Data?
    public let type: DoseType
    /// When the driver programmed the dose. This is the dose's identity — the date every
    /// `NewPumpEvent` for it carries, which hosts dedupe on — so it never moves.
    public let startDate: Date
    /// When the pump reported delivery actually began, for a bolus. See `recordDeliveryStart`.
    public var deliveryStartDate: Date?
    public var estimatedEndDate: Date
    public let value: Double
    public var deliveredUnits: Double = 0
    public let insulinType: InsulinType?
    public let automatic: Bool
    /// A bolus whose `InitiateBolus` went unanswered, until the pump says whether it started it.
    public var isUnconfirmed = false

    public static func == (lhs: UnfinalizedDose, rhs: UnfinalizedDose) -> Bool {
        lhs.bolusId == rhs.bolusId &&
            lhs.tempRateId == rhs.tempRateId &&
            lhs.tempPercent == rhs.tempPercent &&
            lhs.eventRaw == rhs.eventRaw &&
            lhs.type == rhs.type &&
            lhs.startDate == rhs.startDate &&
            lhs.deliveryStartDate == rhs.deliveryStartDate &&
            lhs.estimatedEndDate == rhs.estimatedEndDate &&
            lhs.value == rhs.value &&
            lhs.deliveredUnits == rhs.deliveredUnits &&
            lhs.insulinType == rhs.insulinType &&
            lhs.automatic == rhs.automatic &&
            lhs.isUnconfirmed == rhs.isUnconfirmed
    }

    public init(
        units: Double,
        duration: TimeInterval,
        activationType: BolusActivationType,
        insulinType: InsulinType?,
        bolusId: Int,
        now: Date = Date.now
    ) {
        type = .bolus
        value = units
        startDate = now
        estimatedEndDate = now.addingTimeInterval(duration)
        self.insulinType = insulinType
        automatic = activationType.isAutomatic
        self.bolusId = bolusId
    }

    public init(basalRate: Double, insulinType: InsulinType?, startDate: Date = Date.now) {
        type = .basal
        value = basalRate
        self.startDate = startDate
        estimatedEndDate = startDate
        self.insulinType = insulinType
        automatic = false
    }

    public init(
        tempRate: Double,
        duration: TimeInterval,
        automatic: Bool,
        insulinType: InsulinType?,
        startDate: Date = Date.now,
        tempRateId: Int? = nil,
        tempPercent: Int? = nil,
        eventRaw: Data? = nil
    ) {
        type = .tempBasal
        value = tempRate
        self.startDate = startDate
        self.insulinType = insulinType
        estimatedEndDate = startDate.addingTimeInterval(duration)
        self.automatic = automatic
        self.tempRateId = tempRateId
        self.tempPercent = tempPercent
        self.eventRaw = eventRaw
    }

    public init(suspendStartTime: Date) {
        type = .suspend
        value = 0
        startDate = suspendStartTime
        estimatedEndDate = startDate
        automatic = false // OSAID does not use suspend function
        insulinType = nil
    }

    public init(resumeStartTime: Date, insulinType: InsulinType?) {
        type = .resume
        value = 0
        startDate = resumeStartTime
        estimatedEndDate = startDate
        self.insulinType = insulinType
        automatic = false // OSAID does not use resume function
    }

    /// The start of insulin delivery: the pump's own if we saw it, else when we programmed the
    /// dose. This is what the reported `DoseEntry` starts at, unlike `startDate`.
    public var doseStartDate: Date {
        deliveryStartDate ?? startDate
    }

    /// Records when the pump said delivery began (`CurrentBolusStatus` in the delivering state).
    ///
    /// Clamped into `startDate...now`: residual clock-measurement error cannot move delivery
    /// before the command or into the future.
    public func recordDeliveryStart(_ date: Date, now: Date) {
        deliveryStartDate = min(max(date, startDate), max(now, startDate))
    }

    public init?(rawValue: RawValue) {
        if let rawType = rawValue["type"] as? DoseType.RawValue, let type = DoseType(rawValue: rawType) {
            self.type = type
        } else {
            logger.warning("Couldn't convert type")
            return nil
        }

        if let value = rawValue["value"] as? Double {
            self.value = value
        } else {
            logger.warning("Couldn't convert value")
            return nil
        }

        if let rawStartDate = rawValue["startDate"] as? Date {
            startDate = rawStartDate
        } else {
            logger.warning("Couldn't convert startDate")
            return nil
        }

        if let rawEstimatedEndDate = rawValue["estimatedEndDate"] as? Date {
            estimatedEndDate = rawEstimatedEndDate
        } else {
            logger.warning("Couldn't convert estimatedEndDate")
            return nil
        }

        if let rawDeliveredUnits = rawValue["deliveredUnits"] as? Double {
            deliveredUnits = rawDeliveredUnits
        } else {
            logger.warning("Couldn't convert deliveredUnits")
            return nil
        }

        if let rawInsulinType = rawValue["insulinType"] as? InsulinType.RawValue,
           let insulinType = InsulinType(rawValue: rawInsulinType)
        {
            self.insulinType = insulinType
        } else {
            insulinType = nil
        }

        if let rawAutomatic = rawValue["automatic"] as? Bool {
            automatic = rawAutomatic
        } else {
            logger.warning("Couldn't convert automatic")
            return nil
        }

        deliveryStartDate = rawValue["deliveryStartDate"] as? Date

        if let bolusIdRaw = rawValue["bolusId"] as? Int {
            bolusId = bolusIdRaw
        } else {
            bolusId = nil
        }

        tempRateId = rawValue["tempRateId"] as? Int
        tempPercent = rawValue["tempPercent"] as? Int
        eventRaw = rawValue["eventRaw"] as? Data
        isUnconfirmed = rawValue["isUnconfirmed"] as? Bool ?? false
    }

    public var rawValue: RawValue {
        var raw: RawValue = [:]

        raw["type"] = type.rawValue
        raw["value"] = value
        raw["startDate"] = startDate
        raw["deliveryStartDate"] = deliveryStartDate
        raw["estimatedEndDate"] = estimatedEndDate
        raw["deliveredUnits"] = deliveredUnits
        raw["insulinType"] = insulinType?.rawValue
        raw["automatic"] = automatic
        raw["bolusId"] = bolusId
        raw["tempRateId"] = tempRateId
        raw["tempPercent"] = tempPercent
        raw["eventRaw"] = eventRaw
        raw["isUnconfirmed"] = isUnconfirmed

        return raw
    }

    public func toDoseEntry(
        isMutable: Bool = false,
        useEstimatedEndDate: Bool = false,
        endDate: Date? = nil,
        now: Date = Date.now
    ) -> DoseEntry {
        let endDate = endDate ?? now
        switch type {
        case .bolus:
            var endDate = isMutable || useEstimatedEndDate ? estimatedEndDate : endDate
            if useEstimatedEndDate, endDate > now {
                // The endDate of a bolus cannot be in the future...
                endDate = now
            }

            return DoseEntry(
                type: .bolus,
                startDate: doseStartDate,
                endDate: endDate,
                value: value,
                unit: .units,
                deliveredUnits: isMutable ? nil : deliveredUnits,
                insulinType: insulinType,
                automatic: automatic,
                isMutable: isMutable
            )

        case .basal:
            return DoseEntry(
                type: .basal,
                startDate: startDate,
                value: roundBasalRate(value),
                unit: .unitsPerHour,
                insulinType: insulinType
            )

        case .tempBasal:
            var actualEndDate = isMutable ? estimatedEndDate : endDate
            if !isMutable, actualEndDate > estimatedEndDate {
                // Limit temp basal endDate till duration
                actualEndDate = estimatedEndDate
            }

            let duration = actualEndDate.timeIntervalSince(startDate)
            return DoseEntry(
                type: .tempBasal,
                startDate: startDate,
                endDate: actualEndDate,
                value: value,
                unit: .unitsPerHour,
                deliveredUnits: isMutable ? nil : TandemPumpCapabilities.roundToReportingResolution(value * (duration / .hours(1))),
                insulinType: insulinType,
                automatic: automatic,
                isMutable: isMutable
            )

        case .suspend:
            return DoseEntry(
                suspendDate: startDate,
                automatic: automatic
            )

        case .resume:
            return DoseEntry(
                resumeDate: startDate,
                insulinType: insulinType,
                automatic: automatic
            )
        }
    }

    /// The `raw` every report of this temp basal carries, however it ends: hosts key the dose on
    /// it, so finishing it early must not change it.
    public var tempBasalRaw: Data {
        if let eventRaw {
            return eventRaw
        }
        // Its programmed amount and start, as builds before `eventRaw` keyed it while it ran.
        let programmedUnits = toDoseEntry(isMutable: true).programmedUnits
        return "\(DoseType.tempBasal.rawValue) \(programmedUnits) \(ISO8601DateFormatter().string(from: startDate))"
            .data(using: .utf8) ?? Data([])
    }

    private func roundBasalRate(_ rate: Double) -> Double {
        TandemPumpCapabilities.roundToSupportedBasalRate(rate)
    }

    public static func defaultBasalDose(
        basalSchedule: BasalRateSchedule,
        insulineType: InsulinType?,
        now: Date = Date()
    ) -> UnfinalizedDose {
        let startOfDay = Calendar.current.startOfDay(for: now)
        let nowTimeInterval = now.timeIntervalSince(startOfDay)

        let currentRate = basalSchedule.items.last(where: { $0.startTime < nowTimeInterval })?.value ?? 0
        return UnfinalizedDose(
            basalRate: currentRate,
            insulinType: insulineType,
            startDate: now
        )
    }
}
