import Foundation

/// A case of the pump's account of a dose differing from the driver's. Not actionable — the pump's
/// number is still the one reported — but kept so the disagreement reaches `debugDescription`
/// rather than only a log line (#328).
public struct PumpDiscrepancy: Equatable {
    public enum Kind: String {
        /// `LastBolusStatus` answered for a bolus other than the one asked about.
        case bolusIdMismatch
        /// The pump ended a bolus early, or delivered less than it was asked for.
        case bolusDeliveryIncomplete
        /// A bolus was finalized from the driver's own estimate; the pump never reported a volume.
        case bolusVolumeUnknown
        /// The pump is not running the basal the driver believes it is.
        case basalMismatch
    }

    public let kind: Kind
    public let date: Date
    public let detail: String

    public init(kind: Kind, date: Date = .now, detail: String) {
        self.kind = kind
        self.date = date
        self.detail = detail
    }
}

extension PumpDiscrepancy: RawRepresentable {
    public typealias RawValue = [String: Any]

    public init?(rawValue: RawValue) {
        guard let rawKind = rawValue["kind"] as? Kind.RawValue,
              let kind = Kind(rawValue: rawKind),
              let date = rawValue["date"] as? Date,
              let detail = rawValue["detail"] as? String
        else {
            return nil
        }

        self.init(kind: kind, date: date, detail: detail)
    }

    public var rawValue: RawValue {
        ["kind": kind.rawValue, "date": date, "detail": detail]
    }
}

extension PumpDiscrepancy: CustomStringConvertible {
    public var description: String {
        "\(kind.rawValue) at \(date): \(detail)"
    }
}
