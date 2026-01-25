import Foundation
import LoopKit
import TandemCore

public struct PendingDose: Codable, Equatable {
    public let syncIdentifier: String
    public let dose: DoseEntry
    public let requestedAt: Date

    public init(syncIdentifier: String, dose: DoseEntry, requestedAt: Date) {
        self.syncIdentifier = syncIdentifier
        self.dose = dose
        self.requestedAt = requestedAt
    }
}

public struct TandemPumpManagerState: RawRepresentable, Equatable, CustomDebugStringConvertible {
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
    public var useSilentTones: Bool

    // Pump global settings
    public var buttonAnnun: PumpGlobalsResponse.AnnunciationEnum?
    public var quickBolusAnnun: PumpGlobalsResponse.AnnunciationEnum?
    public var bolusAnnun: PumpGlobalsResponse.AnnunciationEnum?
    public var reminderAnnun: PumpGlobalsResponse.AnnunciationEnum?
    public var alertAnnun: PumpGlobalsResponse.AnnunciationEnum?
    public var alarmAnnun: PumpGlobalsResponse.AnnunciationEnum?
    public var fillTubingAnnun: PumpGlobalsResponse.AnnunciationEnum?

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
    public var lastHistorySequenceNum: UInt32?
    public var lastHistoryReconciliation: Date?
    public var pendingDoses: [PendingDose]

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
        useSilentTones: Bool = false,
        buttonAnnun: PumpGlobalsResponse.AnnunciationEnum? = nil,
        quickBolusAnnun: PumpGlobalsResponse.AnnunciationEnum? = nil,
        bolusAnnun: PumpGlobalsResponse.AnnunciationEnum? = nil,
        reminderAnnun: PumpGlobalsResponse.AnnunciationEnum? = nil,
        alertAnnun: PumpGlobalsResponse.AnnunciationEnum? = nil,
        alarmAnnun: PumpGlobalsResponse.AnnunciationEnum? = nil,
        fillTubingAnnun: PumpGlobalsResponse.AnnunciationEnum? = nil,
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
        insulinType: InsulinType? = nil,
        lastHistorySequenceNum: UInt32? = nil,
        lastHistoryReconciliation: Date? = nil,
        pendingDoses: [PendingDose] = []
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
        self.useSilentTones = useSilentTones
        self.buttonAnnun = buttonAnnun
        self.quickBolusAnnun = quickBolusAnnun
        self.bolusAnnun = bolusAnnun
        self.reminderAnnun = reminderAnnun
        self.alertAnnun = alertAnnun
        self.alarmAnnun = alarmAnnun
        self.fillTubingAnnun = fillTubingAnnun
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
        self.lastHistorySequenceNum = lastHistorySequenceNum
        self.lastHistoryReconciliation = lastHistoryReconciliation
        self.pendingDoses = pendingDoses
    }

    public init?(rawValue: RawValue) {
        latestInsulinOnBoard = rawValue["latestInsulinOnBoard"] as? Double
        useSilentTones = rawValue["useSilentTones"] as? Bool ?? false
        deliveryIsUncertain = rawValue["deliveryIsUncertain"] as? Bool ?? false
        insulinDeliveryActionsEnabled = rawValue["insulinDeliveryActionsEnabled"] as? Bool ?? false
        connectionSharingEnabled = rawValue["connectionSharingEnabled"] as? Bool ?? false
        autoAcknowledgeBasalAlerts = rawValue["autoAcknowledgeBasalAlerts"] as? Bool ?? false
        controlIQEnabled = rawValue["controlIQEnabled"] as? Bool
        controlIQWeight = rawValue["controlIQWeight"] as? Int
        controlIQTotalDailyInsulin = rawValue["controlIQTotalDailyInsulin"] as? Int
        tempRateActive = rawValue["tempRateActive"] as? Bool
        tempRatePercentage = rawValue["tempRatePercentage"] as? Int
        tempRateDuration = rawValue["tempRateDuration"] as? UInt32
        currentBasalRate = rawValue["currentBasalRate"] as? Double
        notificationCount = rawValue["notificationCount"] as? Int
        lastHistorySequenceNum = rawValue["lastHistorySequenceNum"] as? UInt32

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

        if let scheduleRaw = rawValue["basalRateSchedule"] as? [String: Any] {
            basalRateSchedule = TandemPumpManagerState.decodeBasalSchedule(from: scheduleRaw)
        } else {
            basalRateSchedule = nil
        }

        if let rawInsulinType = rawValue["insulinType"] as? InsulinType.RawValue {
            insulinType = InsulinType(rawValue: rawInsulinType)
        } else {
            insulinType = nil
        }

        if let modeRaw = rawValue["controlIQUserMode"] as? Int {
            controlIQUserMode = ControlIQUserMode(rawValue: modeRaw)
        } else {
            controlIQUserMode = nil
        }

        if let buttonAnnunRaw = rawValue["buttonAnnun"] as? Int {
            buttonAnnun = PumpGlobalsResponse.AnnunciationEnum(rawValue: buttonAnnunRaw)
        } else {
            buttonAnnun = nil
        }

        if let quickBolusAnnunRaw = rawValue["quickBolusAnnun"] as? Int {
            quickBolusAnnun = PumpGlobalsResponse.AnnunciationEnum(rawValue: quickBolusAnnunRaw)
        } else {
            quickBolusAnnun = nil
        }

        if let bolusAnnunRaw = rawValue["bolusAnnun"] as? Int {
            bolusAnnun = PumpGlobalsResponse.AnnunciationEnum(rawValue: bolusAnnunRaw)
        } else {
            bolusAnnun = nil
        }

        if let reminderAnnunRaw = rawValue["reminderAnnun"] as? Int {
            reminderAnnun = PumpGlobalsResponse.AnnunciationEnum(rawValue: reminderAnnunRaw)
        } else {
            reminderAnnun = nil
        }

        if let alertAnnunRaw = rawValue["alertAnnun"] as? Int {
            alertAnnun = PumpGlobalsResponse.AnnunciationEnum(rawValue: alertAnnunRaw)
        } else {
            alertAnnun = nil
        }

        if let alarmAnnunRaw = rawValue["alarmAnnun"] as? Int {
            alarmAnnun = PumpGlobalsResponse.AnnunciationEnum(rawValue: alarmAnnunRaw)
        } else {
            alarmAnnun = nil
        }

        if let fillTubingAnnunRaw = rawValue["fillTubingAnnun"] as? Int {
            fillTubingAnnun = PumpGlobalsResponse.AnnunciationEnum(rawValue: fillTubingAnnunRaw)
        } else {
            fillTubingAnnun = nil
        }

        if let lastControlIQInterval = rawValue["lastControlIQUpdate"] as? TimeInterval {
            lastControlIQUpdate = Date(timeIntervalSinceReferenceDate: lastControlIQInterval)
        } else {
            lastControlIQUpdate = nil
        }

        if let lastTempRateInterval = rawValue["lastTempRateUpdate"] as? TimeInterval {
            lastTempRateUpdate = Date(timeIntervalSinceReferenceDate: lastTempRateInterval)
        } else {
            lastTempRateUpdate = nil
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

        if let lastNotificationInterval = rawValue["lastNotificationUpdate"] as? TimeInterval {
            lastNotificationUpdate = Date(timeIntervalSinceReferenceDate: lastNotificationInterval)
        } else {
            lastNotificationUpdate = nil
        }

        if let rawInsulinType = rawValue["insulinType"] as? InsulinType.RawValue {
            insulinType = InsulinType(rawValue: rawInsulinType)
        } else {
            insulinType = nil
        }

        if let lastHistoryInterval = rawValue["lastHistoryReconciliation"] as? TimeInterval {
            lastHistoryReconciliation = Date(timeIntervalSinceReferenceDate: lastHistoryInterval)
        } else {
            lastHistoryReconciliation = nil
        }

        if let pendingData = rawValue["pendingDoses"] as? Data,
           let decoded = try? PropertyListDecoder().decode([PendingDose].self, from: pendingData)
        {
            pendingDoses = decoded
        } else {
            pendingDoses = []
        }
    }

    public var rawValue: RawValue {
        var raw: RawValue = [:]

        raw["pumpState"] = pumpState?.rawValue
        raw["lastReconciliation"] = lastReconciliation?.timeIntervalSinceReferenceDate
        raw["latestInsulinOnBoard"] = latestInsulinOnBoard
        raw["deliveryIsUncertain"] = deliveryIsUncertain
        raw["insulinDeliveryActionsEnabled"] = insulinDeliveryActionsEnabled
        raw["connectionSharingEnabled"] = connectionSharingEnabled
        raw["autoAcknowledgeBasalAlerts"] = autoAcknowledgeBasalAlerts
        raw["buttonAnnun"] = buttonAnnun?.rawValue
        raw["quickBolusAnnun"] = quickBolusAnnun?.rawValue
        raw["bolusAnnun"] = bolusAnnun?.rawValue
        raw["reminderAnnun"] = reminderAnnun?.rawValue
        raw["alertAnnun"] = alertAnnun?.rawValue
        raw["alarmAnnun"] = alarmAnnun?.rawValue
        raw["fillTubingAnnun"] = fillTubingAnnun?.rawValue
        raw["controlIQEnabled"] = controlIQEnabled
        raw["controlIQUserMode"] = controlIQUserMode?.rawValue
        raw["controlIQWeight"] = controlIQWeight
        raw["controlIQTotalDailyInsulin"] = controlIQTotalDailyInsulin
        raw["lastControlIQUpdate"] = lastControlIQUpdate?.timeIntervalSinceReferenceDate
        raw["tempRateActive"] = tempRateActive
        raw["tempRatePercentage"] = tempRatePercentage
        raw["tempRateDuration"] = tempRateDuration
        raw["lastTempRateUpdate"] = lastTempRateUpdate?.timeIntervalSinceReferenceDate
        raw["currentBasalRate"] = currentBasalRate
        raw["lastBasalRateUpdate"] = lastBasalRateUpdate?.timeIntervalSinceReferenceDate
        raw["basalStatusIcon"] = basalStatusIcon?.rawValue
        raw["bolusStatusIcon"] = bolusStatusIcon?.rawValue
        raw["cgmAlertIcon"] = cgmAlertIcon?.rawValue
        raw["notificationCount"] = notificationCount
        raw["lastNotificationUpdate"] = lastNotificationUpdate?.timeIntervalSinceReferenceDate
        raw["insulinType"] = insulinType
        raw["useSilentTones"] = useSilentTones
        raw["lastHistorySequenceNum"] = lastHistorySequenceNum
        raw["lastHistoryReconciliation"] = lastHistoryReconciliation?.timeIntervalSinceReferenceDate

        let settingsRaw = settings.rawValue
        if !settingsRaw.isEmpty {
            raw["settings"] = settingsRaw
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

        if let basalRateSchedule = basalRateSchedule,
           let encodedSchedule = TandemPumpManagerState.encodeBasalSchedule(basalRateSchedule)
        {
            raw["basalRateSchedule"] = encodedSchedule
        }

        if !pendingDoses.isEmpty,
           let encoded = try? PropertyListEncoder().encode(pendingDoses)
        {
            raw["pendingDoses"] = encoded
        }

        return raw
    }

    public var debugDescription: String {
        [
            "### TandemPumpManagerState",
            "* pumpState: \(String(describing: pumpState?.debugDescription))",
            "* lastReconciliation: \(String(describing: lastReconciliation))",
            "* settings: \(settings)",
            "* latestInsulinOnBoard: \(String(describing: latestInsulinOnBoard))",
            "* lastReservoirReading: \(String(describing: lastReservoirReading))",
            "* lastBatteryReading: \(String(describing: lastBatteryReading))",
            "* basalDeliveryState: \(String(describing: basalDeliveryState))",
            "* lastBasalStatusDate: \(String(describing: lastBasalStatusDate))",
            "* bolusState: \(bolusState)",
            "* deliveryIsUncertain: \(deliveryIsUncertain)",
            "* basalRateSchedule: \(String(describing: basalRateSchedule))",
            "* insulinDeliveryActionsEnabled: \(insulinDeliveryActionsEnabled)",
            "* connectionSharingEnabled: \(connectionSharingEnabled)",
            "* autoAcknowledgeBasalAlerts: \(autoAcknowledgeBasalAlerts)",
            "* useSilentTones: \(useSilentTones)",
            "* buttonAnnun: \(String(describing: buttonAnnun))",
            "* bolusAnnun: \(String(describing: bolusAnnun))",
            "* quickBolusAnnun: \(String(describing: quickBolusAnnun))",
            "* reminderAnnun: \(String(describing: reminderAnnun))",
            "* alertAnnun: \(String(describing: alertAnnun))",
            "* alarmAnnun: \(String(describing: alarmAnnun))",
            "* fillTubingAnnun: \(String(describing: fillTubingAnnun))",
            "* controlIQEnabled: \(String(describing: controlIQEnabled))",
            "* controlIQUserMode: \(String(describing: controlIQUserMode))",
            "* controlIQWeight: \(String(describing: controlIQWeight))",
            "* controlIQTotalDailyInsulin: \(String(describing: controlIQTotalDailyInsulin))",
            "* lastControlIQUpdate: \(String(describing: lastControlIQUpdate))",
            "* tempRateActive: \(String(describing: tempRateActive))",
            "* tempRatePercentage: \(String(describing: tempRatePercentage))",
            "* tempRateDuration: \(String(describing: tempRateDuration))",
            "* lastTempRateUpdate: \(String(describing: lastTempRateUpdate))",
            "* currentBasalRate: \(String(describing: currentBasalRate))",
            "* lastBasalRateUpdate: \(String(describing: lastBasalRateUpdate))",
            "* basalStatusIcon: \(String(describing: basalStatusIcon))",
            "* bolusStatusIcon: \(String(describing: bolusStatusIcon))",
            "* cgmAlertIcon: \(String(describing: cgmAlertIcon))",
            "* notificationCount: \(String(describing: notificationCount))",
            "* lastNotificationUpdate: \(String(describing: lastNotificationUpdate))"
        ].joined(separator: "\n")
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
            lhs.useSilentTones == rhs.useSilentTones &&
            lhs.buttonAnnun == rhs.buttonAnnun &&
            lhs.quickBolusAnnun == rhs.quickBolusAnnun &&
            lhs.bolusAnnun == rhs.bolusAnnun &&
            lhs.reminderAnnun == rhs.reminderAnnun &&
            lhs.alertAnnun == rhs.alertAnnun &&
            lhs.alarmAnnun == rhs.alarmAnnun &&
            lhs.fillTubingAnnun == rhs.fillTubingAnnun &&
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
            lhs.insulinType == rhs.insulinType &&
            lhs.lastHistorySequenceNum == rhs.lastHistorySequenceNum &&
            lhs.lastHistoryReconciliation == rhs.lastHistoryReconciliation &&
            lhs.pendingDoses == rhs.pendingDoses
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
