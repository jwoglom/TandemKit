import Foundation
import LoopKit
import TandemCore

public struct TandemPumpManagerState: RawRepresentable, Equatable {
    public typealias RawValue = [String: Any]

    public static let version = 2

    public var pumpState: PumpState?
    public var lastReconciliation: Date?
    public var lastReservoirReading: ReservoirValue?
    public var basalDeliveryState: PumpManagerStatus.BasalDeliveryState?
    public var bolusState: PumpManagerStatus.BolusState
    public var deliveryIsUncertain: Bool

    public init(
        pumpState: PumpState?,
        lastReconciliation: Date? = nil,
        lastReservoirReading: ReservoirValue? = nil,
        basalDeliveryState: PumpManagerStatus.BasalDeliveryState? = nil,
        bolusState: PumpManagerStatus.BolusState = .noBolus,
        deliveryIsUncertain: Bool = false
    ) {
        self.pumpState = pumpState
        self.lastReconciliation = lastReconciliation
        self.lastReservoirReading = lastReservoirReading
        self.basalDeliveryState = basalDeliveryState
        self.bolusState = bolusState
        self.deliveryIsUncertain = deliveryIsUncertain
    }

    public init?(rawValue: RawValue) {
        guard let version = rawValue["version"] as? Int,
              (1...TandemPumpManagerState.version).contains(version) else {
            return nil
        }

        if let pumpStateRaw = rawValue["pumpState"] as? PumpState.RawValue {
            self.pumpState = PumpState(rawValue: pumpStateRaw)
        } else {
            self.pumpState = nil
        }

        if let lastReconciliationInterval = rawValue["lastReconciliation"] as? TimeInterval {
            self.lastReconciliation = Date(timeIntervalSinceReferenceDate: lastReconciliationInterval)
        } else {
            self.lastReconciliation = nil
        }

        if let reservoirRaw = rawValue["lastReservoirReading"] as? [String: Any] {
            self.lastReservoirReading = TandemPumpManagerState.decodeReservoirValue(from: reservoirRaw)
        } else {
            self.lastReservoirReading = nil
        }

        if let basalRaw = rawValue["basalDeliveryState"] as? [String: Any] {
            self.basalDeliveryState = TandemPumpManagerState.decodeBasalState(from: basalRaw)
        } else {
            self.basalDeliveryState = nil
        }

        if let bolusRaw = rawValue["bolusState"] as? [String: Any],
           let decodedBolusState = TandemPumpManagerState.decodeBolusState(from: bolusRaw) {
            self.bolusState = decodedBolusState
        } else {
            self.bolusState = .noBolus
        }

        if let deliveryIsUncertain = rawValue["deliveryIsUncertain"] as? Bool {
            self.deliveryIsUncertain = deliveryIsUncertain
        } else {
            self.deliveryIsUncertain = false
        }
    }

    public var rawValue: RawValue {
        var raw: RawValue = [
            "version": TandemPumpManagerState.version
        ]

        if let pumpState = pumpState {
            raw["pumpState"] = pumpState.rawValue
        }

        if let lastReconciliation = lastReconciliation {
            raw["lastReconciliation"] = lastReconciliation.timeIntervalSinceReferenceDate
        }

        if let lastReservoirReading = lastReservoirReading {
            raw["lastReservoirReading"] = TandemPumpManagerState.encodeReservoirValue(lastReservoirReading)
        }

        if let basalDeliveryState = basalDeliveryState,
           let encodedBasalState = TandemPumpManagerState.encodeBasalState(basalDeliveryState) {
            raw["basalDeliveryState"] = encodedBasalState
        }

        if let encodedBolusState = TandemPumpManagerState.encodeBolusState(bolusState) {
            raw["bolusState"] = encodedBolusState
        }

        raw["deliveryIsUncertain"] = deliveryIsUncertain

        return raw
    }
}

public extension TandemPumpManagerState {
    static func == (lhs: TandemPumpManagerState, rhs: TandemPumpManagerState) -> Bool {
        return lhs.pumpState == rhs.pumpState &&
            lhs.lastReconciliation == rhs.lastReconciliation &&
            TandemPumpManagerState.reservoirValuesEqual(lhs.lastReservoirReading, rhs.lastReservoirReading) &&
            lhs.basalDeliveryState == rhs.basalDeliveryState &&
            lhs.bolusState == rhs.bolusState &&
            lhs.deliveryIsUncertain == rhs.deliveryIsUncertain
    }
}

private extension TandemPumpManagerState {
    private static func encodeReservoirValue(_ value: ReservoirValue) -> [String: Any] {
        return [
            "startDate": value.startDate.timeIntervalSinceReferenceDate,
            "unitVolume": value.unitVolume
        ]
    }

    private static func decodeReservoirValue(from raw: [String: Any]) -> ReservoirValue? {
        guard let startInterval = raw["startDate"] as? TimeInterval,
              let unitVolume = raw["unitVolume"] as? Double else {
            return nil
        }

        return SimpleReservoirValue(
            startDate: Date(timeIntervalSinceReferenceDate: startInterval),
            unitVolume: unitVolume
        )
    }

    private static func encodeBasalState(_ state: PumpManagerStatus.BasalDeliveryState) -> [String: Any]? {
        var raw: [String: Any] = [:]

        switch state {
        case .active(let date):
            raw["case"] = "active"
            raw["date"] = date.timeIntervalSinceReferenceDate
        case .initiatingTempBasal:
            raw["case"] = "initiatingTempBasal"
        case .tempBasal(let dose):
            raw["case"] = "tempBasal"
            if let data = try? PropertyListEncoder().encode(dose) {
                raw["dose"] = data
            }
        case .cancelingTempBasal:
            raw["case"] = "cancelingTempBasal"
        case .suspending:
            raw["case"] = "suspending"
        case .suspended(let date):
            raw["case"] = "suspended"
            raw["date"] = date.timeIntervalSinceReferenceDate
        case .resuming:
            raw["case"] = "resuming"
        }

        return raw
    }

    private static func decodeBasalState(from raw: [String: Any]) -> PumpManagerStatus.BasalDeliveryState? {
        guard let caseName = raw["case"] as? String else {
            return nil
        }

        switch caseName {
        case "active":
            if let interval = raw["date"] as? TimeInterval {
                return .active(Date(timeIntervalSinceReferenceDate: interval))
            }
        case "initiatingTempBasal":
            return .initiatingTempBasal
        case "tempBasal":
            if let data = raw["dose"] as? Data,
               let dose = try? PropertyListDecoder().decode(DoseEntry.self, from: data) {
                return .tempBasal(dose)
            }
        case "cancelingTempBasal":
            return .cancelingTempBasal
        case "suspending":
            return .suspending
        case "suspended":
            if let interval = raw["date"] as? TimeInterval {
                return .suspended(Date(timeIntervalSinceReferenceDate: interval))
            }
        case "resuming":
            return .resuming
        default:
            return nil
        }

        return nil
    }

    private static func encodeBolusState(_ state: PumpManagerStatus.BolusState) -> [String: Any]? {
        var raw: [String: Any] = [:]

        switch state {
        case .noBolus:
            raw["case"] = "noBolus"
        case .initiating:
            raw["case"] = "initiating"
        case .inProgress(let dose):
            raw["case"] = "inProgress"
            if let data = try? PropertyListEncoder().encode(dose) {
                raw["dose"] = data
            }
        case .canceling:
            raw["case"] = "canceling"
        }

        return raw
    }

    private static func decodeBolusState(from raw: [String: Any]) -> PumpManagerStatus.BolusState? {
        guard let caseName = raw["case"] as? String else {
            return nil
        }

        switch caseName {
        case "noBolus":
            return .noBolus
        case "initiating":
            return .initiating
        case "inProgress":
            if let data = raw["dose"] as? Data,
               let dose = try? PropertyListDecoder().decode(DoseEntry.self, from: data) {
                return .inProgress(dose)
            }
        case "canceling":
            return .canceling
        default:
            return nil
        }

        return nil
    }
}
    static func reservoirValuesEqual(_ lhs: ReservoirValue?, _ rhs: ReservoirValue?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (let left?, let right?):
            return left.startDate == right.startDate && left.unitVolume == right.unitVolume
        default:
            return false
        }
    }
