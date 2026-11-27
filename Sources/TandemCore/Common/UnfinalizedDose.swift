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
    /// The `raw` minted from the pump's `bolusId` or `tempRateId` when the app commanded the dose.
    public var eventRaw: Data?
    /// A host overwrites its stored dose's decision with each report's, so every report carries this.
    public var decisionId: UUID?
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
    /// A temp basal the host set through `enactTempBasal`, as opposed to one set from TandemKit's
    /// settings or adopted from pump history, which `automatic` alone does not tell apart.
    public let setByHost: Bool
    /// A bolus whose `InitiateBolus` went unanswered, until the pump says whether it started it.
    public var isUnconfirmed = false

    public static func == (lhs: UnfinalizedDose, rhs: UnfinalizedDose) -> Bool {
        lhs.bolusId == rhs.bolusId &&
            lhs.tempRateId == rhs.tempRateId &&
            lhs.tempPercent == rhs.tempPercent &&
            lhs.eventRaw == rhs.eventRaw &&
            lhs.decisionId == rhs.decisionId &&
            lhs.type == rhs.type &&
            lhs.startDate == rhs.startDate &&
            lhs.deliveryStartDate == rhs.deliveryStartDate &&
            lhs.estimatedEndDate == rhs.estimatedEndDate &&
            lhs.value == rhs.value &&
            lhs.deliveredUnits == rhs.deliveredUnits &&
            lhs.insulinType == rhs.insulinType &&
            lhs.automatic == rhs.automatic &&
            lhs.setByHost == rhs.setByHost &&
            lhs.isUnconfirmed == rhs.isUnconfirmed
    }

    public init(
        units: Double,
        duration: TimeInterval,
        activationType: BolusActivationType,
        insulinType: InsulinType?,
        bolusId: Int,
        decisionId: UUID? = nil,
        now: Date = Date.now
    ) {
        type = .bolus
        value = units
        startDate = now
        estimatedEndDate = now.addingTimeInterval(duration)
        self.insulinType = insulinType
        automatic = activationType.isAutomatic
        setByHost = false
        self.bolusId = bolusId
        self.decisionId = decisionId
    }

    public init(basalRate: Double, insulinType: InsulinType?, startDate: Date = Date.now) {
        type = .basal
        value = basalRate
        self.startDate = startDate
        estimatedEndDate = startDate
        self.insulinType = insulinType
        automatic = false
        setByHost = false
    }

    public init(
        tempRate: Double,
        duration: TimeInterval,
        automatic: Bool,
        setByHost: Bool = false,
        insulinType: InsulinType?,
        startDate: Date = Date.now,
        tempRateId: Int? = nil,
        tempPercent: Int? = nil,
        eventRaw: Data? = nil,
        decisionId: UUID? = nil
    ) {
        type = .tempBasal
        value = tempRate
        self.startDate = startDate
        self.insulinType = insulinType
        estimatedEndDate = startDate.addingTimeInterval(duration)
        self.automatic = automatic
        self.setByHost = setByHost
        self.tempRateId = tempRateId
        self.tempPercent = tempPercent
        self.eventRaw = eventRaw
        self.decisionId = decisionId
    }

    public init(suspendStartTime: Date) {
        type = .suspend
        value = 0
        startDate = suspendStartTime
        estimatedEndDate = startDate
        automatic = false // OSAID does not use suspend function
        setByHost = false
        insulinType = nil
    }

    public init(resumeStartTime: Date, insulinType: InsulinType?) {
        type = .resume
        value = 0
        startDate = resumeStartTime
        estimatedEndDate = startDate
        self.insulinType = insulinType
        automatic = false // OSAID does not use resume function
        setByHost = false
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

        // Saved before the flag existed reads as not the host's: a temp taken for the host's may be
        // replaced without asking.
        setByHost = rawValue["setByHost"] as? Bool ?? false
        deliveryStartDate = rawValue["deliveryStartDate"] as? Date

        if let bolusIdRaw = rawValue["bolusId"] as? Int {
            bolusId = bolusIdRaw
        } else {
            bolusId = nil
        }

        tempRateId = rawValue["tempRateId"] as? Int
        tempPercent = rawValue["tempPercent"] as? Int
        eventRaw = rawValue["eventRaw"] as? Data
        decisionId = (rawValue["decisionId"] as? String).flatMap(UUID.init(uuidString:))
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
        raw["setByHost"] = setByHost
        raw["bolusId"] = bolusId
        raw["tempRateId"] = tempRateId
        raw["tempPercent"] = tempPercent
        raw["eventRaw"] = eventRaw
        raw["decisionId"] = decisionId?.uuidString
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
                decisionId: decisionId,
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
                decisionId: nil,
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
                decisionId: decisionId,
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

    /// This temp basal at `rate` from `start` to `end`: a part after a segment change, a continuation
    /// or a remainder. Every re-statement goes through here, so each part keeps the temp's flags.
    public func tempBasalPart(rate: Double, from start: Date, until end: Date, eventRaw: Data? = nil) -> UnfinalizedDose {
        UnfinalizedDose(
            tempRate: rate,
            duration: end.timeIntervalSince(start),
            automatic: automatic,
            setByHost: setByHost,
            insulinType: insulinType,
            startDate: start,
            tempRateId: tempRateId,
            tempPercent: tempPercent,
            eventRaw: eventRaw,
            decisionId: decisionId
        )
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
        // The wall clock's time of day, which the time since midnight is not on a DST change's day.
        let local = now.timeIntervalSince1970 + TimeInterval(basalSchedule.timeZone.secondsFromGMT(for: now))
        let nowTimeInterval = local - (local / 86400).rounded(.down) * 86400

        let currentRate = basalSchedule.items.last(where: { $0.startTime < nowTimeInterval })?.value ?? 0
        return UnfinalizedDose(
            basalRate: currentRate,
            insulinType: insulineType,
            startDate: now
        )
    }
}

extension UnfinalizedDose: CustomDebugStringConvertible {
    public var debugDescription: String {
        var parts: [String]
        switch type {
        case .bolus:
            parts = ["bolus \(value) U, delivered \(deliveredUnits) U"]
        case .basal,
             .tempBasal:
            parts = ["\(type) \(value) U/hr"]
        case .resume,
             .suspend:
            parts = ["\(type)"]
        }
        parts.append(estimatedEndDate == startDate ? "at \(startDate)" : "\(startDate) to \(estimatedEndDate)")
        if let deliveryStartDate { parts.append("delivery started \(deliveryStartDate)") }
        if automatic { parts.append("automatic") }
        if setByHost { parts.append("set by host") }
        if let bolusId { parts.append("bolusId \(bolusId)") }
        if let tempRateId { parts.append("tempRateId \(tempRateId)") }
        if let tempPercent { parts.append("tempPercent \(tempPercent)%") }
        if let eventRaw { parts.append("eventRaw \(eventRaw.hexadecimalString)") }
        if let decisionId { parts.append("decision \(decisionId)") }
        if isUnconfirmed { parts.append("unconfirmed") }
        return parts.joined(separator: ", ")
    }
}
