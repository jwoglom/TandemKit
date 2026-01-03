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

    public enum ControlIQUserMode: Int, RawRepresentable, Equatable {
        case standard = 0
        case sleep = 2
        case exercise = 3
    }

    public enum HomeScreenBasalStatus: Int, RawRepresentable, Equatable {
        case active = 0
        case tempRate = 2
        case suspended = 4
    }

    public enum HomeScreenBolusStatus: Int, RawRepresentable, Equatable {
        case none = 200
        case bolus = 0
    }

    public enum HomeScreenCGMAlert: Int, RawRepresentable, Equatable {
        case noError = 255
        case low = 16
        case high = 17
    }

    public static let version = 5

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
    public var insulinDeliveryActionsEnabled: Bool
    public var connectionSharingEnabled: Bool
    public var autoAcknowledgeBasalAlerts: Bool

    // Control-IQ state
    public var controlIQEnabled: Bool?
    public var controlIQUserMode: ControlIQUserMode?
    public var controlIQWeight: Int?
    public var controlIQTotalDailyInsulin: Int?
    public var lastControlIQUpdate: Date?

    // Temp rate (additional detail beyond existing basal state)
    public var tempRateActive: Bool?
    public var tempRatePercentage: Int?
    public var tempRateDuration: UInt32?
    public var lastTempRateUpdate: Date?

    // Current basal rate for display
    public var currentBasalRate: Double?
    public var lastBasalRateUpdate: Date?

    // Status icons from HomeScreenMirror
    public var basalStatusIcon: HomeScreenBasalStatus?
    public var bolusStatusIcon: HomeScreenBolusStatus?
    public var cgmAlertIcon: HomeScreenCGMAlert?

    // Notification count
    public var notificationCount: Int?
    public var lastNotificationUpdate: Date?
    public var insulinType: InsulinType?

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
        insulinDeliveryActionsEnabled: Bool = false,
        connectionSharingEnabled: Bool = false,
        autoAcknowledgeBasalAlerts: Bool = false,
        controlIQEnabled: Bool? = nil,
        controlIQUserMode: ControlIQUserMode? = nil,
        controlIQWeight: Int? = nil,
        controlIQTotalDailyInsulin: Int? = nil,
        lastControlIQUpdate: Date? = nil,
        tempRateActive: Bool? = nil,
        tempRatePercentage: Int? = nil,
        tempRateDuration: UInt32? = nil,
        lastTempRateUpdate: Date? = nil,
        currentBasalRate: Double? = nil,
        lastBasalRateUpdate: Date? = nil,
        basalStatusIcon: HomeScreenBasalStatus? = nil,
        bolusStatusIcon: HomeScreenBolusStatus? = nil,
        cgmAlertIcon: HomeScreenCGMAlert? = nil,
        notificationCount: Int? = nil,
        lastNotificationUpdate: Date? = nil,
        insulinType: InsulinType? = nil
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
        self.insulinDeliveryActionsEnabled = insulinDeliveryActionsEnabled
        self.connectionSharingEnabled = connectionSharingEnabled
        self.autoAcknowledgeBasalAlerts = autoAcknowledgeBasalAlerts
        self.controlIQEnabled = controlIQEnabled
        self.controlIQUserMode = controlIQUserMode
        self.controlIQWeight = controlIQWeight
        self.controlIQTotalDailyInsulin = controlIQTotalDailyInsulin
        self.lastControlIQUpdate = lastControlIQUpdate
        self.tempRateActive = tempRateActive
        self.tempRatePercentage = tempRatePercentage
        self.tempRateDuration = tempRateDuration
        self.lastTempRateUpdate = lastTempRateUpdate
        self.currentBasalRate = currentBasalRate
        self.lastBasalRateUpdate = lastBasalRateUpdate
        self.basalStatusIcon = basalStatusIcon
        self.bolusStatusIcon = bolusStatusIcon
        self.cgmAlertIcon = cgmAlertIcon
        self.notificationCount = notificationCount
        self.lastNotificationUpdate = lastNotificationUpdate
        self.insulinType = insulinType
    }

    public init?(rawValue: RawValue) {
        guard let version = rawValue["version"] as? Int,
              (1 ... TandemPumpManagerState.version).contains(version)
        else {
            return nil
        }

        if let pumpStateRaw = rawValue["pumpState"] as? PumpState.RawValue {
            pumpState = PumpState(rawValue: pumpStateRaw)
        } else {
            pumpState = nil
        }

        if let lastReconciliationInterval = rawValue["lastReconciliation"] as? TimeInterval {
            lastReconciliation = Date(timeIntervalSinceReferenceDate: lastReconciliationInterval)
        } else {
            lastReconciliation = nil
        }

        if let settingsRaw = rawValue["settings"] as? TandemPumpManagerSettings.RawValue,
           let decodedSettings = TandemPumpManagerSettings(rawValue: settingsRaw)
        {
            settings = decodedSettings
        } else {
            settings = .default
        }

        if let latestInsulinOnBoard = rawValue["latestInsulinOnBoard"] as? Double {
            self.latestInsulinOnBoard = latestInsulinOnBoard
        } else {
            latestInsulinOnBoard = nil
        }

        if let reservoirRaw = rawValue["lastReservoirReading"] as? [String: Any] {
            lastReservoirReading = TandemPumpManagerState.decodeReservoirValue(from: reservoirRaw)
        } else {
            lastReservoirReading = nil
        }

        if let batteryRaw = rawValue["lastBatteryReading"] as? [String: Any] {
            lastBatteryReading = TandemPumpManagerState.decodeBatteryReading(from: batteryRaw)
        } else {
            lastBatteryReading = nil
        }

        if let basalRaw = rawValue["basalDeliveryState"] as? [String: Any] {
            basalDeliveryState = TandemPumpManagerState.decodeBasalState(from: basalRaw)
        } else {
            basalDeliveryState = nil
        }

        if let lastBasalDateInterval = rawValue["lastBasalStatusDate"] as? TimeInterval {
            lastBasalStatusDate = Date(timeIntervalSinceReferenceDate: lastBasalDateInterval)
        } else {
            lastBasalStatusDate = nil
        }

        if let bolusRaw = rawValue["bolusState"] as? [String: Any],
           let decodedBolusState = TandemPumpManagerState.decodeBolusState(from: bolusRaw)
        {
            bolusState = decodedBolusState
        } else {
            bolusState = .noBolus
        }

        if let deliveryIsUncertain = rawValue["deliveryIsUncertain"] as? Bool {
            self.deliveryIsUncertain = deliveryIsUncertain
        } else {
            deliveryIsUncertain = false
        }

        if let scheduleRaw = rawValue["basalRateSchedule"] as? [String: Any] {
            basalRateSchedule = TandemPumpManagerState.decodeBasalSchedule(from: scheduleRaw)
        } else {
            basalRateSchedule = nil
        }

        if let insulinActionsEnabled = rawValue["insulinDeliveryActionsEnabled"] as? Bool {
            insulinDeliveryActionsEnabled = insulinActionsEnabled
        } else {
            insulinDeliveryActionsEnabled = false
        }

        if let connectionSharingEnabled = rawValue["connectionSharingEnabled"] as? Bool {
            self.connectionSharingEnabled = connectionSharingEnabled
        } else {
            connectionSharingEnabled = false
        }

        if let autoAcknowledgeBasalAlerts = rawValue["autoAcknowledgeBasalAlerts"] as? Bool {
            self.autoAcknowledgeBasalAlerts = autoAcknowledgeBasalAlerts
        } else {
            autoAcknowledgeBasalAlerts = false
        }

        if let rawInsulinType = rawValue["insulinType"] as? InsulinType.RawValue {
            insulinType = InsulinType(rawValue: rawInsulinType)
        } else {
            insulinType = nil
        }

        // Version 5+ properties
        if version >= 5 {
            if let controlIQEnabled = rawValue["controlIQEnabled"] as? Bool {
                self.controlIQEnabled = controlIQEnabled
            } else {
                controlIQEnabled = nil
            }

            if let modeRaw = rawValue["controlIQUserMode"] as? Int {
                controlIQUserMode = ControlIQUserMode(rawValue: modeRaw)
            } else {
                controlIQUserMode = nil
            }

            if let controlIQWeight = rawValue["controlIQWeight"] as? Int {
                self.controlIQWeight = controlIQWeight
            } else {
                controlIQWeight = nil
            }

            if let controlIQTotalDailyInsulin = rawValue["controlIQTotalDailyInsulin"] as? Int {
                self.controlIQTotalDailyInsulin = controlIQTotalDailyInsulin
            } else {
                controlIQTotalDailyInsulin = nil
            }

            if let lastControlIQInterval = rawValue["lastControlIQUpdate"] as? TimeInterval {
                lastControlIQUpdate = Date(timeIntervalSinceReferenceDate: lastControlIQInterval)
            } else {
                lastControlIQUpdate = nil
            }

            if let tempRateActive = rawValue["tempRateActive"] as? Bool {
                self.tempRateActive = tempRateActive
            } else {
                tempRateActive = nil
            }

            if let tempRatePercentage = rawValue["tempRatePercentage"] as? Int {
                self.tempRatePercentage = tempRatePercentage
            } else {
                tempRatePercentage = nil
            }

            if let tempRateDuration = rawValue["tempRateDuration"] as? UInt32 {
                self.tempRateDuration = tempRateDuration
            } else {
                tempRateDuration = nil
            }

            if let lastTempRateInterval = rawValue["lastTempRateUpdate"] as? TimeInterval {
                lastTempRateUpdate = Date(timeIntervalSinceReferenceDate: lastTempRateInterval)
            } else {
                lastTempRateUpdate = nil
            }

            if let currentBasalRate = rawValue["currentBasalRate"] as? Double {
                self.currentBasalRate = currentBasalRate
            } else {
                currentBasalRate = nil
            }

            if let lastBasalRateInterval = rawValue["lastBasalRateUpdate"] as? TimeInterval {
                lastBasalRateUpdate = Date(timeIntervalSinceReferenceDate: lastBasalRateInterval)
            } else {
                lastBasalRateUpdate = nil
            }

            if let basalIconRaw = rawValue["basalStatusIcon"] as? Int {
                basalStatusIcon = HomeScreenBasalStatus(rawValue: basalIconRaw)
            } else {
                basalStatusIcon = nil
            }

            if let bolusIconRaw = rawValue["bolusStatusIcon"] as? Int {
                bolusStatusIcon = HomeScreenBolusStatus(rawValue: bolusIconRaw)
            } else {
                bolusStatusIcon = nil
            }

            if let cgmIconRaw = rawValue["cgmAlertIcon"] as? Int {
                cgmAlertIcon = HomeScreenCGMAlert(rawValue: cgmIconRaw)
            } else {
                cgmAlertIcon = nil
            }

            if let notificationCount = rawValue["notificationCount"] as? Int {
                self.notificationCount = notificationCount
            } else {
                notificationCount = nil
            }

            if let lastNotificationInterval = rawValue["lastNotificationUpdate"] as? TimeInterval {
                lastNotificationUpdate = Date(timeIntervalSinceReferenceDate: lastNotificationInterval)
            } else {
                lastNotificationUpdate = nil
            }
        } else {
            // Pre-v5: all new fields are nil
            controlIQEnabled = nil
            controlIQUserMode = nil
            controlIQWeight = nil
            controlIQTotalDailyInsulin = nil
            lastControlIQUpdate = nil
            tempRateActive = nil
            tempRatePercentage = nil
            tempRateDuration = nil
            lastTempRateUpdate = nil
            currentBasalRate = nil
            lastBasalRateUpdate = nil
            basalStatusIcon = nil
            bolusStatusIcon = nil
            cgmAlertIcon = nil
            notificationCount = nil
            lastNotificationUpdate = nil
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
           let encodedBasalState = TandemPumpManagerState.encodeBasalState(basalDeliveryState)
        {
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
           let encodedSchedule = TandemPumpManagerState.encodeBasalSchedule(basalRateSchedule)
        {
            raw["basalRateSchedule"] = encodedSchedule
        }

        raw["insulinDeliveryActionsEnabled"] = insulinDeliveryActionsEnabled
        raw["connectionSharingEnabled"] = connectionSharingEnabled
        raw["autoAcknowledgeBasalAlerts"] = autoAcknowledgeBasalAlerts

        // Version 5+ properties
        if let controlIQEnabled = controlIQEnabled {
            raw["controlIQEnabled"] = controlIQEnabled
        }

        if let controlIQUserMode = controlIQUserMode {
            raw["controlIQUserMode"] = controlIQUserMode.rawValue
        }

        if let controlIQWeight = controlIQWeight {
            raw["controlIQWeight"] = controlIQWeight
        }

        if let controlIQTotalDailyInsulin = controlIQTotalDailyInsulin {
            raw["controlIQTotalDailyInsulin"] = controlIQTotalDailyInsulin
        }

        if let lastControlIQUpdate = lastControlIQUpdate {
            raw["lastControlIQUpdate"] = lastControlIQUpdate.timeIntervalSinceReferenceDate
        }

        if let tempRateActive = tempRateActive {
            raw["tempRateActive"] = tempRateActive
        }

        if let tempRatePercentage = tempRatePercentage {
            raw["tempRatePercentage"] = tempRatePercentage
        }

        if let tempRateDuration = tempRateDuration {
            raw["tempRateDuration"] = tempRateDuration
        }

        if let lastTempRateUpdate = lastTempRateUpdate {
            raw["lastTempRateUpdate"] = lastTempRateUpdate.timeIntervalSinceReferenceDate
        }

        if let currentBasalRate = currentBasalRate {
            raw["currentBasalRate"] = currentBasalRate
        }

        if let lastBasalRateUpdate = lastBasalRateUpdate {
            raw["lastBasalRateUpdate"] = lastBasalRateUpdate.timeIntervalSinceReferenceDate
        }

        if let basalStatusIcon = basalStatusIcon {
            raw["basalStatusIcon"] = basalStatusIcon.rawValue
        }

        if let bolusStatusIcon = bolusStatusIcon {
            raw["bolusStatusIcon"] = bolusStatusIcon.rawValue
        }

        if let cgmAlertIcon = cgmAlertIcon {
            raw["cgmAlertIcon"] = cgmAlertIcon.rawValue
        }

        if let notificationCount = notificationCount {
            raw["notificationCount"] = notificationCount
        }

        if let lastNotificationUpdate = lastNotificationUpdate {
            raw["lastNotificationUpdate"] = lastNotificationUpdate.timeIntervalSinceReferenceDate
        }
        raw["insulinType"] = insulinType

        return raw
    }
}

public extension TandemPumpManagerState {
    static func == (lhs: TandemPumpManagerState, rhs: TandemPumpManagerState) -> Bool {
        lhs.pumpState == rhs.pumpState &&
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
            lhs.insulinDeliveryActionsEnabled == rhs.insulinDeliveryActionsEnabled &&
            lhs.connectionSharingEnabled == rhs.connectionSharingEnabled &&
            lhs.autoAcknowledgeBasalAlerts == rhs.autoAcknowledgeBasalAlerts &&
            lhs.controlIQEnabled == rhs.controlIQEnabled &&
            lhs.controlIQUserMode == rhs.controlIQUserMode &&
            lhs.controlIQWeight == rhs.controlIQWeight &&
            lhs.controlIQTotalDailyInsulin == rhs.controlIQTotalDailyInsulin &&
            lhs.lastControlIQUpdate == rhs.lastControlIQUpdate &&
            lhs.tempRateActive == rhs.tempRateActive &&
            lhs.tempRatePercentage == rhs.tempRatePercentage &&
            lhs.tempRateDuration == rhs.tempRateDuration &&
            lhs.lastTempRateUpdate == rhs.lastTempRateUpdate &&
            lhs.currentBasalRate == rhs.currentBasalRate &&
            lhs.lastBasalRateUpdate == rhs.lastBasalRateUpdate &&
            lhs.basalStatusIcon == rhs.basalStatusIcon &&
            lhs.bolusStatusIcon == rhs.bolusStatusIcon &&
            lhs.cgmAlertIcon == rhs.cgmAlertIcon &&
            lhs.notificationCount == rhs.notificationCount &&
            lhs.lastNotificationUpdate == rhs.lastNotificationUpdate &&
            lhs.insulinType == rhs.insulinType
    }
}

private extension TandemPumpManagerState {
    static func encodeReservoirValue(_ value: ReservoirValue) -> [String: Any] {
        [
            "startDate": value.startDate.timeIntervalSinceReferenceDate,
            "unitVolume": value.unitVolume
        ]
    }

    static func decodeReservoirValue(from raw: [String: Any]) -> ReservoirValue? {
        guard let startInterval = raw["startDate"] as? TimeInterval,
              let unitVolume = raw["unitVolume"] as? Double
        else {
            return nil
        }

        return SimpleReservoirValue(
            startDate: Date(timeIntervalSinceReferenceDate: startInterval),
            unitVolume: unitVolume
        )
    }

    static func encodeBatteryReading(_ reading: BatteryReading) -> [String: Any] {
        [
            "date": reading.date.timeIntervalSinceReferenceDate,
            "chargeRemaining": reading.chargeRemaining
        ]
    }

    static func decodeBatteryReading(from raw: [String: Any]) -> BatteryReading? {
        guard let timestamp = raw["date"] as? TimeInterval,
              let chargeRemaining = raw["chargeRemaining"] as? Double
        else {
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
        case let .active(date):
            raw["case"] = "active"
            raw["date"] = date.timeIntervalSinceReferenceDate
        case .initiatingTempBasal:
            raw["case"] = "initiatingTempBasal"
        case let .tempBasal(dose):
            raw["case"] = "tempBasal"
            if let data = try? PropertyListEncoder().encode(dose) {
                raw["dose"] = data
            }
        case .cancelingTempBasal:
            raw["case"] = "cancelingTempBasal"
        case .suspending:
            raw["case"] = "suspending"
        case let .suspended(date):
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
               let dose = try? PropertyListDecoder().decode(DoseEntry.self, from: data)
            {
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
        case let .inProgress(dose):
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
               let dose = try? PropertyListDecoder().decode(DoseEntry.self, from: data)
            {
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
              let timeZoneIdentifier = raw["timeZoneIdentifier"] as? String
        else {
            return nil
        }

        let items: [RepeatingScheduleValue<Double>] = itemDictionaries.compactMap { entry in
            guard let startTime = entry["startTime"] as? TimeInterval,
                  let value = entry["value"] as? Double
            else {
                return nil
            }

            return RepeatingScheduleValue(startTime: startTime, value: value)
        }

        guard !items.isEmpty else {
            return nil
        }

        let timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return BasalRateSchedule(dailyItems: items, timeZone: timeZone)
    }

    static func reservoirValuesEqual(_ lhs: ReservoirValue?, _ rhs: ReservoirValue?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (left?, right?):
            return left.startDate == right.startDate && left.unitVolume == right.unitVolume
        default:
            return false
        }
    }
}
