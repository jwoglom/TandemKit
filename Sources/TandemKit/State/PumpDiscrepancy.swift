import Foundation
import LoopKit

public struct PumpDiscrepancy: Equatable {
    public let date: Date
    public let detail: Detail

    public enum Detail: Equatable {
        /// `LastBolusStatus` answered about `reported` rather than the bolus asked about.
        /// `reported` is nil when a V3 response carried no record for it at all.
        case bolusIdMismatch(bolusId: Int, reported: Int?)
        /// The pump ended a bolus early, or delivered less than it was asked for.
        case bolusDeliveryIncomplete(
            bolusId: Int?,
            programmedUnits: Double,
            deliveredUnits: Double,
            endReason: LastBolusStatusAbstractResponse.BolusStatus?
        )
        /// The pump never reported a delivered volume, so the dose was finalized from the
        /// driver's own estimate.
        case bolusVolumeUnknown(bolusId: Int, estimatedUnits: Double)
        /// The pump is not running the kind of basal the driver believes it is.
        case basalTypeMismatch(expected: DoseType, reported: DoseType, secondsRemaining: TimeInterval)
        /// The pump's temp basal is not running at the rate the driver reported to the host.
        case basalRateMismatch(expectedUnitsPerHour: Double, reportedUnitsPerHour: Double)
    }

    public init(date: Date = .now, detail: Detail) {
        self.date = date
        self.detail = detail
    }
}

public extension PumpDiscrepancy.Detail {
    enum Kind: String {
        case bolusIdMismatch
        case bolusDeliveryIncomplete
        case bolusVolumeUnknown
        case basalTypeMismatch
        case basalRateMismatch
    }

    var kind: Kind {
        switch self {
        case .bolusIdMismatch: return .bolusIdMismatch
        case .bolusDeliveryIncomplete: return .bolusDeliveryIncomplete
        case .bolusVolumeUnknown: return .bolusVolumeUnknown
        case .basalTypeMismatch: return .basalTypeMismatch
        case .basalRateMismatch: return .basalRateMismatch
        }
    }
}

public extension PumpDiscrepancy {
    var kind: Detail.Kind { detail.kind }
}

extension PumpDiscrepancy: RawRepresentable {
    public typealias RawValue = [String: Any]

    public init?(rawValue: RawValue) {
        guard let date = rawValue["date"] as? Date,
              let rawKind = rawValue["kind"] as? Detail.Kind.RawValue,
              let kind = Detail.Kind(rawValue: rawKind)
        else {
            return nil
        }

        let bolusId = rawValue["bolusId"] as? Int
        let endReason = (rawValue["endReason"] as? Int).flatMap(LastBolusStatusAbstractResponse.BolusStatus.init(rawValue:))

        switch kind {
        case .bolusIdMismatch:
            guard let bolusId else { return nil }
            detail = .bolusIdMismatch(bolusId: bolusId, reported: rawValue["reportedBolusId"] as? Int)

        case .bolusDeliveryIncomplete:
            guard let programmed = rawValue["programmedUnits"] as? Double,
                  let delivered = rawValue["deliveredUnits"] as? Double
            else {
                return nil
            }
            detail = .bolusDeliveryIncomplete(
                bolusId: bolusId,
                programmedUnits: programmed,
                deliveredUnits: delivered,
                endReason: endReason
            )

        case .bolusVolumeUnknown:
            guard let bolusId, let estimated = rawValue["estimatedUnits"] as? Double else { return nil }
            detail = .bolusVolumeUnknown(bolusId: bolusId, estimatedUnits: estimated)

        case .basalTypeMismatch:
            guard let rawExpected = rawValue["expectedType"] as? DoseType.RawValue,
                  let expected = DoseType(rawValue: rawExpected),
                  let rawReported = rawValue["reportedType"] as? DoseType.RawValue,
                  let reported = DoseType(rawValue: rawReported),
                  let remaining = rawValue["secondsRemaining"] as? TimeInterval
            else {
                return nil
            }
            detail = .basalTypeMismatch(expected: expected, reported: reported, secondsRemaining: remaining)

        case .basalRateMismatch:
            guard let expected = rawValue["expectedUnitsPerHour"] as? Double,
                  let reported = rawValue["reportedUnitsPerHour"] as? Double
            else {
                return nil
            }
            detail = .basalRateMismatch(expectedUnitsPerHour: expected, reportedUnitsPerHour: reported)
        }

        self.date = date
    }

    public var rawValue: RawValue {
        var raw: RawValue = ["date": date, "kind": kind.rawValue]

        switch detail {
        case .bolusIdMismatch(let bolusId, let reported):
            raw["bolusId"] = bolusId
            raw["reportedBolusId"] = reported

        case .bolusDeliveryIncomplete(let bolusId, let programmed, let delivered, let endReason):
            raw["bolusId"] = bolusId
            raw["programmedUnits"] = programmed
            raw["deliveredUnits"] = delivered
            raw["endReason"] = endReason?.rawValue

        case .bolusVolumeUnknown(let bolusId, let estimated):
            raw["bolusId"] = bolusId
            raw["estimatedUnits"] = estimated

        case .basalTypeMismatch(let expected, let reported, let remaining):
            raw["expectedType"] = expected.rawValue
            raw["reportedType"] = reported.rawValue
            raw["secondsRemaining"] = remaining

        case .basalRateMismatch(let expected, let reported):
            raw["expectedUnitsPerHour"] = expected
            raw["reportedUnitsPerHour"] = reported
        }

        return raw
    }
}

extension PumpDiscrepancy: CustomStringConvertible {
    public var description: String {
        "\(kind.rawValue) at \(date): \(detail)"
    }
}
