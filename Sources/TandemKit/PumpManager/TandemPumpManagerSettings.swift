import Foundation

public struct TandemPumpManagerSettings: RawRepresentable, Equatable {
    public typealias RawValue = [String: Any]

    public var maxBolus: Double?
    public var maxTempBasalRate: Double?
    public var maxBasalScheduleEntry: Double?
    public var maxInsulinOnBoard: Double?

    public init(
        maxBolus: Double? = nil,
        maxTempBasalRate: Double? = nil,
        maxBasalScheduleEntry: Double? = nil,
        maxInsulinOnBoard: Double? = nil
    ) {
        self.maxBolus = maxBolus
        self.maxTempBasalRate = maxTempBasalRate
        self.maxBasalScheduleEntry = maxBasalScheduleEntry
        self.maxInsulinOnBoard = maxInsulinOnBoard
    }

    public init?(rawValue: RawValue) {
        func double(from value: Any?) -> Double? {
            switch value {
            case let doubleValue as Double:
                return doubleValue
            case let number as NSNumber:
                return number.doubleValue
            default:
                return nil
            }
        }

        maxBolus = double(from: rawValue["maxBolus"])
        maxTempBasalRate = double(from: rawValue["maxTempBasalRate"])
        maxBasalScheduleEntry = double(from: rawValue["maxBasalScheduleEntry"])
        maxInsulinOnBoard = double(from: rawValue["maxInsulinOnBoard"])
    }

    public var rawValue: RawValue {
        var raw: RawValue = [:]

        if let maxBolus = maxBolus {
            raw["maxBolus"] = maxBolus
        }

        if let maxTempBasalRate = maxTempBasalRate {
            raw["maxTempBasalRate"] = maxTempBasalRate
        }

        if let maxBasalScheduleEntry = maxBasalScheduleEntry {
            raw["maxBasalScheduleEntry"] = maxBasalScheduleEntry
        }

        if let maxInsulinOnBoard = maxInsulinOnBoard {
            raw["maxInsulinOnBoard"] = maxInsulinOnBoard
        }

        return raw
    }
}

public extension TandemPumpManagerSettings {
    static let `default` = TandemPumpManagerSettings()
}

public enum TandemPumpManagerValidationError: Error, Equatable {
    case invalidBolusAmount(requested: Double)
    case maximumBolusExceeded(requested: Double, maximum: Double)
    case insulinOnBoardLimitExceeded(currentIOB: Double, requested: Double, maximum: Double)
    case invalidTempBasalRate(requested: Double)
    case maximumTempBasalRateExceeded(requested: Double, maximum: Double)
    case invalidTempBasalDuration(requested: TimeInterval)
}
