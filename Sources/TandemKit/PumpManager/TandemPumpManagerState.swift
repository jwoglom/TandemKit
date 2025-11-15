import Foundation
import LoopKit
import TandemCore

public struct TandemPumpManagerState: RawRepresentable, Equatable {
    public typealias RawValue = [String: Any]

    public struct BatteryReading: Equatable {
        public let date: Date
        public let chargeRemaining: Double

        public init(date: Date, chargeRemaining: Double) {
            self.date = date
            self.chargeRemaining = chargeRemaining
        }
    }

    public struct CGMReading: Equatable {
        public let date: Date
        public let value: Double?
        public let egvStatusId: Int
        public let trendRate: Int

        public init(date: Date, value: Double?, egvStatusId: Int, trendRate: Int) {
            self.date = date
            self.value = value
            self.egvStatusId = egvStatusId
            self.trendRate = trendRate
        }

        public var egvStatus: CurrentEGVGuiDataResponse.EGVStatus? {
            CurrentEGVGuiDataResponse.EGVStatus(rawValue: egvStatusId)
        }

        public func makeDisplay() -> PumpManagerStatus.GlucoseDisplay {
            let unit = HKUnit.milligramsPerDeciliter()
            let quantity = value.map { HKQuantity(unit: unit, doubleValue: $0) }
            let isValidStatus = egvStatus != .INVALID && egvStatus != .UNAVAILABLE
            let isValid = isValidStatus && value != nil

            return PumpManagerStatus.GlucoseDisplay(
                isStateValid: isValid,
                startDate: date,
                quantity: quantity,
                trendType: Self.mapTrend(trendRate),
                trendRateUnit: nil,
                trendRateValue: nil,
                isLocal: true,
                wasUserEntered: false,
                value: value,
                unitString: "mg/dL"
            )
        }

        private static func mapTrend(_ rate: Int) -> GlucoseTrend? {
            switch rate {
            case 0:
                return .doubleDown
            case 1:
                return .singleDown
            case 2:
                return .fortyFiveDown
            case 3:
                return .flat
            case 4:
                return .fortyFiveUp
            case 5:
                return .singleUp
            case 6:
                return .doubleUp
            default:
                return nil
            }
        }
    }

    public static let version = 4

    public var pumpState: PumpState?
    public var lastReconciliation: Date?
    public var settings: TandemPumpManagerSettings
    public var latestInsulinOnBoard: Double?
    public var lastReservoirReading: ReservoirValue?
    public var lastBatteryReading: BatteryReading?
    public var basalDeliveryState: PumpManagerStatus.BasalDeliveryState?
    public var lastBasalStatusDate: Date?
    public var bolusState: PumpManagerStatus.BolusState
    public var deliveryIsUncertain: Bool
    public var basalRateSchedule: BasalRateSchedule?
    public var lastCGMReading: CGMReading?
    public var activeAlertIDs: Set<Int>
    public var activeAlarmIDs: Set<Int>

    public init(
        pumpState: PumpState?,
        lastReconciliation: Date? = nil,
        settings: TandemPumpManagerSettings = .default,
        latestInsulinOnBoard: Double? = nil,
        lastReservoirReading: ReservoirValue? = nil,
        lastBatteryReading: BatteryReading? = nil,
        basalDeliveryState: PumpManagerStatus.BasalDeliveryState? = nil,
        lastBasalStatusDate: Date? = nil,
        bolusState: PumpManagerStatus.BolusState = .noBolus,
        deliveryIsUncertain: Bool = false,
        basalRateSchedule: BasalRateSchedule? = nil,
        lastCGMReading: CGMReading? = nil,
        activeAlertIDs: Set<Int> = [],
        activeAlarmIDs: Set<Int> = []
    ) {
        self.pumpState = pumpState
        self.lastReconciliation = lastReconciliation
        self.settings = settings
        self.latestInsulinOnBoard = latestInsulinOnBoard
        self.lastReservoirReading = lastReservoirReading
        self.lastBatteryReading = lastBatteryReading
        self.basalDeliveryState = basalDeliveryState
        self.lastBasalStatusDate = lastBasalStatusDate
        self.bolusState = bolusState
        self.deliveryIsUncertain = deliveryIsUncertain
        self.basalRateSchedule = basalRateSchedule
        self.lastCGMReading = lastCGMReading
        self.activeAlertIDs = activeAlertIDs
        self.activeAlarmIDs = activeAlarmIDs
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

        if let settingsRaw = rawValue["settings"] as? TandemPumpManagerSettings.RawValue,
           let decodedSettings = TandemPumpManagerSettings(rawValue: settingsRaw) {
            self.settings = decodedSettings
        } else {
            self.settings = .default
        }

        if let latestInsulinOnBoard = rawValue["latestInsulinOnBoard"] as? Double {
            self.latestInsulinOnBoard = latestInsulinOnBoard
        } else {
            self.latestInsulinOnBoard = nil
        }

        if let reservoirRaw = rawValue["lastReservoirReading"] as? [String: Any] {
            self.lastReservoirReading = TandemPumpManagerState.decodeReservoirValue(from: reservoirRaw)
        } else {
            self.lastReservoirReading = nil
        }

        if let batteryRaw = rawValue["lastBatteryReading"] as? [String: Any] {
            self.lastBatteryReading = TandemPumpManagerState.decodeBatteryReading(from: batteryRaw)
        } else {
            self.lastBatteryReading = nil
        }

        if let basalRaw = rawValue["basalDeliveryState"] as? [String: Any] {
            self.basalDeliveryState = TandemPumpManagerState.decodeBasalState(from: basalRaw)
        } else {
            self.basalDeliveryState = nil
        }

        if let lastBasalDateInterval = rawValue["lastBasalStatusDate"] as? TimeInterval {
            self.lastBasalStatusDate = Date(timeIntervalSinceReferenceDate: lastBasalDateInterval)
        } else {
            self.lastBasalStatusDate = nil
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

        if let scheduleRaw = rawValue["basalRateSchedule"] as? [String: Any] {
            self.basalRateSchedule = TandemPumpManagerState.decodeBasalSchedule(from: scheduleRaw)
        } else {
            self.basalRateSchedule = nil
        }

        if let cgmRaw = rawValue["lastCGMReading"] as? [String: Any] {
            self.lastCGMReading = TandemPumpManagerState.decodeCGMReading(from: cgmRaw)
        } else {
            self.lastCGMReading = nil
        }

        if let alertArray = rawValue["activeAlertIDs"] as? [Int] {
            self.activeAlertIDs = Set(alertArray)
        } else {
            self.activeAlertIDs = []
        }

        if let alarmArray = rawValue["activeAlarmIDs"] as? [Int] {
            self.activeAlarmIDs = Set(alarmArray)
        } else {
            self.activeAlarmIDs = []
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

        let settingsRaw = settings.rawValue
        if !settingsRaw.isEmpty {
            raw["settings"] = settingsRaw
        }

        if let latestInsulinOnBoard = latestInsulinOnBoard {
            raw["latestInsulinOnBoard"] = latestInsulinOnBoard
        }

        if let lastReservoirReading = lastReservoirReading {
            raw["lastReservoirReading"] = TandemPumpManagerState.encodeReservoirValue(lastReservoirReading)
        }

        if let lastBatteryReading = lastBatteryReading {
            raw["lastBatteryReading"] = TandemPumpManagerState.encodeBatteryReading(lastBatteryReading)
        }

        if let basalDeliveryState = basalDeliveryState,
           let encodedBasalState = TandemPumpManagerState.encodeBasalState(basalDeliveryState) {
            raw["basalDeliveryState"] = encodedBasalState
        }

        if let lastBasalStatusDate = lastBasalStatusDate {
            raw["lastBasalStatusDate"] = lastBasalStatusDate.timeIntervalSinceReferenceDate
        }

        if let encodedBolusState = TandemPumpManagerState.encodeBolusState(bolusState) {
            raw["bolusState"] = encodedBolusState
        }

        raw["deliveryIsUncertain"] = deliveryIsUncertain

        if let basalRateSchedule = basalRateSchedule,
           let encodedSchedule = TandemPumpManagerState.encodeBasalSchedule(basalRateSchedule) {
            raw["basalRateSchedule"] = encodedSchedule
        }

        if let lastCGMReading = lastCGMReading {
            raw["lastCGMReading"] = TandemPumpManagerState.encodeCGMReading(lastCGMReading)
        }

        if !activeAlertIDs.isEmpty {
            raw["activeAlertIDs"] = Array(activeAlertIDs).sorted()
        }

        if !activeAlarmIDs.isEmpty {
            raw["activeAlarmIDs"] = Array(activeAlarmIDs).sorted()
        }

        return raw
    }
}

public extension TandemPumpManagerState {
    static func == (lhs: TandemPumpManagerState, rhs: TandemPumpManagerState) -> Bool {
        return lhs.pumpState == rhs.pumpState &&
            lhs.lastReconciliation == rhs.lastReconciliation &&
            lhs.settings == rhs.settings &&
            lhs.latestInsulinOnBoard == rhs.latestInsulinOnBoard &&
            TandemPumpManagerState.reservoirValuesEqual(lhs.lastReservoirReading, rhs.lastReservoirReading) &&
            lhs.lastBatteryReading == rhs.lastBatteryReading &&
            lhs.basalDeliveryState == rhs.basalDeliveryState &&
            lhs.lastBasalStatusDate == rhs.lastBasalStatusDate &&
            lhs.bolusState == rhs.bolusState &&
            lhs.deliveryIsUncertain == rhs.deliveryIsUncertain &&
            lhs.basalRateSchedule == rhs.basalRateSchedule &&
            lhs.lastCGMReading == rhs.lastCGMReading &&
            lhs.activeAlertIDs == rhs.activeAlertIDs &&
            lhs.activeAlarmIDs == rhs.activeAlarmIDs
    }
}

extension TandemPumpManagerState {
    static func encodeCGMReading(_ reading: CGMReading) -> [String: Any] {
        var raw: [String: Any] = [
            "date": reading.date.timeIntervalSinceReferenceDate,
            "egvStatusId": reading.egvStatusId,
            "trendRate": reading.trendRate
        ]

        if let value = reading.value {
            raw["value"] = value
        }

        return raw
    }

    static func decodeCGMReading(from raw: [String: Any]) -> CGMReading? {
        guard let dateInterval = raw["date"] as? TimeInterval,
              let egvStatusId = raw["egvStatusId"] as? Int,
              let trendRate = raw["trendRate"] as? Int else {
            return nil
        }

        let value = raw["value"] as? Double
        let date = Date(timeIntervalSinceReferenceDate: dateInterval)
        return CGMReading(date: date, value: value, egvStatusId: egvStatusId, trendRate: trendRate)
    }
}

public extension TandemPumpManagerState {
    var glucoseDisplay: PumpManagerStatus.GlucoseDisplay? {
        lastCGMReading?.makeDisplay()
    }
}

private extension TandemPumpManagerState {
    static func encodeReservoirValue(_ value: ReservoirValue) -> [String: Any] {
        return [
            "startDate": value.startDate.timeIntervalSinceReferenceDate,
            "unitVolume": value.unitVolume
        ]
    }

    static func decodeReservoirValue(from raw: [String: Any]) -> ReservoirValue? {
        guard let startInterval = raw["startDate"] as? TimeInterval,
              let unitVolume = raw["unitVolume"] as? Double else {
            return nil
        }

        return SimpleReservoirValue(
            startDate: Date(timeIntervalSinceReferenceDate: startInterval),
            unitVolume: unitVolume
        )
    }

    static func encodeBatteryReading(_ reading: BatteryReading) -> [String: Any] {
        return [
            "date": reading.date.timeIntervalSinceReferenceDate,
            "chargeRemaining": reading.chargeRemaining
        ]
    }

    static func decodeBatteryReading(from raw: [String: Any]) -> BatteryReading? {
        guard let timestamp = raw["date"] as? TimeInterval,
              let chargeRemaining = raw["chargeRemaining"] as? Double else {
            return nil
        }

        return BatteryReading(
            date: Date(timeIntervalSinceReferenceDate: timestamp),
            chargeRemaining: chargeRemaining
        )
    }

    static func encodeBasalState(_ state: PumpManagerStatus.BasalDeliveryState) -> [String: Any]? {
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

    static func decodeBasalState(from raw: [String: Any]) -> PumpManagerStatus.BasalDeliveryState? {
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

    static func encodeBolusState(_ state: PumpManagerStatus.BolusState) -> [String: Any]? {
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

    static func decodeBolusState(from raw: [String: Any]) -> PumpManagerStatus.BolusState? {
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

    static func encodeBasalSchedule(_ schedule: BasalRateSchedule) -> [String: Any]? {
        let items = schedule.items.map { item -> [String: Any] in
            [
                "startTime": item.startTime,
                "value": item.value
            ]
        }

        return [
            "items": items,
            "timeZoneIdentifier": schedule.timeZone.identifier
        ]
    }

    static func decodeBasalSchedule(from raw: [String: Any]) -> BasalRateSchedule? {
        guard let itemDictionaries = raw["items"] as? [[String: Any]],
              let timeZoneIdentifier = raw["timeZoneIdentifier"] as? String else {
            return nil
        }

        let items: [RepeatingScheduleValue<Double>] = itemDictionaries.compactMap { entry in
            guard let startTime = entry["startTime"] as? TimeInterval,
                  let value = entry["value"] as? Double else {
                return nil
            }

            return RepeatingScheduleValue(startTime: startTime, value: value)
        }

        guard !items.isEmpty else {
            return nil
        }

        let timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return BasalRateSchedule(items: items, timeZone: timeZone)
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
}
