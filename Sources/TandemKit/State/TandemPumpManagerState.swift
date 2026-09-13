import Foundation
import HealthKit
import LoopKit

public struct TandemPumpManagerState: RawRepresentable {
    public typealias RawValue = [String: Any]

    public struct BatteryReading: Equatable {
        public let date: Date
        public let chargeRemaining: Double
        /// Whether the pump was charging. Pumps on API versions without a charging field
        /// always report false.
        public let isCharging: Bool

        public init(date: Date, chargeRemaining: Double, isCharging: Bool = false) {
            self.date = date
            self.chargeRemaining = chargeRemaining
            self.isCharging = isCharging
        }
    }

    public enum ControlIQUserMode: Int, RawRepresentable, Equatable {
        case standard = 0
        case sleep = 1
        case exercise = 2

        public static func fromUserModeType(_ userModeType: ControlIQInfoAbstractResponse.UserModeType) -> ControlIQUserMode? {
            switch userModeType {
            case .standard:
                return .standard
            case .sleep:
                return .sleep
            case .exercise:
                return .exercise
            default:
                return nil as ControlIQUserMode?
            }
        }
    }

    public var onboarded: Bool = false
    public var pumpState: PumpState
    public var isConnected: Bool = false
    public var lastReconciliation: Date?
    public var settings: TandemPumpManagerSettings = .default
    public var featureFlags: TandemFeatureFlags = .default
    public var latestInsulinOnBoard: Double?
    public var lastReservoirReading: ReservoirValue?
    /// Cleared once `lastReservoirReading` has reached the delegate. Persisted so a reading taken
    /// while none was attached survives a relaunch.
    public var lastReservoirReadingNeedsReport: Bool = false
    public var lastBatteryReading: BatteryReading?
    public var lastBasalStatusDate: Date?
    /// How far the driver has read this pump's history log, and the earliest date it may report
    /// events for. Persisted so a relaunch resumes an incremental read instead of re-walking the
    /// pump's whole history into an empty session store.
    public var historyBackfill: HistoryBackfillState?
    public var bolusState: PumpManagerStatus.BolusState = .noBolus
    public var insulinType: InsulinType?
    public var bolusDose: UnfinalizedDose?
    public var pendingBolusFinalization: UnfinalizedDose?
    /// How often the pump has contradicted the driver, and the most recent case. See
    /// `PumpDiscrepancy`.
    public var pumpDiscrepancyCount: Int = 0
    public var lastPumpDiscrepancy: PumpDiscrepancy?
    public var basalDose: UnfinalizedDose
    public var basalRateSchedule: BasalRateSchedule
    /// Basal min/max alerts are auto-acknowledged unconditionally: oref routinely sets a zero
    /// basal rate, which the pump would otherwise announce with a notification every time. Kept as
    /// state rather than a constant so tests can exercise the disabled path, but there is no
    /// user-facing way to turn it off.
    public var autoAcknowledgeBasalAlerts: Bool = true
    public var useSilentTones: Bool = false

    // Pump time
    public var currentPumpTime: Date?
    public var lastPumpTimeCheckDate: Date?

    // Pump global settings
    public var lastSettingsCheckedAt: Date?
    public var quickBolusAnnun: PumpGlobalsResponse.AnnunciationEnum?
    public var reminderAnnun: PumpGlobalsResponse.AnnunciationEnum?
    public var alertAnnun: PumpGlobalsResponse.AnnunciationEnum?
    public var alarmAnnun: PumpGlobalsResponse.AnnunciationEnum?
    public var generalAnnun: PumpGlobalsResponse.AnnunciationEnum?

    // Quick bolus settings (from PumpGlobalsResponse)
    public var quickBolusEnabled: Bool?
    public var quickBolusEntryType: Int?
    public var quickBolusIncrementUnits: Int?
    public var quickBolusIncrementCarbs: Int?
    public var quickBolusStatus: Int?

    // Delivery limits (from BasalLimitSettingsResponse / GlobalMaxBolusSettingsResponse)
    public var maxBasalLimitMilliunits: Int?
    public var maxBasalLimitDefaultMilliunits: Int?
    public var maxBolusLimitMilliunits: Int?
    public var maxBolusLimitDefaultMilliunits: Int?

    // Control-IQ state
    public var useControlIQ: Bool = false
    public var pendingEnableClosedLoop: Bool = false
    public var controlIQEnabled: Bool?
    public var controlIQUserMode: ControlIQUserMode?
    /// Body weight Control-IQ is configured with, always in pounds -- the unit
    /// `ChangeControlIQSettingsRequest` carries on the wire, regardless of the unit the pump
    /// displays. nil when Control-IQ has never been configured on the pump.
    public var controlIQWeightLbs: Int?
    /// Unit the pump displays the weight in. Display only; `controlIQWeightLbs` is the value sent.
    public var controlIQWeightUnit: ControlIQInfoAbstractResponse.WeightUnit?
    /// nil when Control-IQ has never been configured on the pump.
    public var controlIQTotalDailyInsulin: Int?
    public var lastControlIQUpdate: Date?

    // CGM sensor session on the pump. `nil` means we have not (yet) been able to read the pump's
    // CGM status — which is not the same as "no sensor", so callers must not treat it as absence.
    public var cgmSessionState: CGMStatusV2Response.SessionState?
    public var lastCGMStatusUpdate: Date?

    /// Whether the pump has a CGM sensor session established — running (`active`) or warming up
    /// (`startPending`). `nil` when the pump's CGM status is unknown.
    ///
    /// Control-IQ can only close the loop with a CGM feeding the pump, so this is what gates the
    /// "no CGM connected" warning; see `CGMStatusV2Response.isSensorSessionConfigured`.
    public var isCGMSensorSessionConfigured: Bool? {
        switch cgmSessionState {
        case .none:
            return nil
        case .active, .startPending:
            return true
        case .stopPending, .stopped, .unknown:
            return false
        }
    }

    // Alert snooze settings
    public var alertSnoozeEnabled: Bool = false
    public var alertSnoozeDuration: TimeInterval = .minutes(10)

    // Notification count
    public var notificationCount: Int?
    public var lastNotificationUpdate: Date?

    // LoopKit alert surfacing
    /// Stable identifiers (`NotificationItem.stableIdentifier`) of pump notifications
    /// currently issued as LoopKit alerts. Persisted so alerts issued before an app restart
    /// are retracted (not re-issued) once the pump reports them cleared.
    public var issuedAlertIdentifiers: Set<String> = []
    /// Whether CGM alerts are forwarded as LoopKit alerts in addition to alerts, alarms,
    /// and malfunctions. Off by default: users running their CGM vendor's app already
    /// receive these and duplicates are noisy.
    public var forwardCGMAlerts: Bool = false

    // Consumable change tracking
    /// Last cannula / infusion-set change. Set when the user fills the cannula.
    public var lastSiteChangeDate: Date?
    /// Last cartridge / reservoir change. Set when the user changes the cartridge.
    public var lastCartridgeChangeDate: Date?
    /// Prime amount, in units, of the last successful cannula fill. Persisted so the fill
    /// cannula wizard can pre-fill the amount the user chose last time instead of the default.
    public var lastCannulaFillAmount: Double?

    public init(basalRateSchedule: BasalRateSchedule) {
        self.basalRateSchedule = basalRateSchedule
        pumpState = PumpState()
        basalDose = .defaultBasalDose(basalSchedule: basalRateSchedule, insulineType: nil)
    }

    public init(rawValue: RawValue) {
        onboarded = rawValue["onboarded"] as? Bool ?? false
        isConnected = false // To prevent having an old isConnected state
        latestInsulinOnBoard = rawValue["latestInsulinOnBoard"] as? Double
        useSilentTones = rawValue["useSilentTones"] as? Bool ?? false
        // Intentionally ignores any persisted value: state saved before auto-acknowledge became
        // mandatory may hold `false`, and those pumps should migrate on, not stay off.
        autoAcknowledgeBasalAlerts = true
        useControlIQ = rawValue["useControlIQ"] as? Bool ?? false
        pendingEnableClosedLoop = rawValue["pendingEnableClosedLoop"] as? Bool ?? false
        controlIQEnabled = rawValue["controlIQEnabled"] as? Bool
        // The legacy "controlIQWeight" key is deliberately not read: it stored whatever unit the
        // pump reported in, so an old value cannot be safely interpreted as pounds. It is
        // repopulated by the next `fetchControlIQStatus`, i.e. on the next sync.
        controlIQWeightLbs = rawValue["controlIQWeightLbs"] as? Int
        controlIQWeightUnit = (rawValue["controlIQWeightUnit"] as? Int)
            .flatMap(ControlIQInfoAbstractResponse.WeightUnit.init(rawValue:))
        controlIQTotalDailyInsulin = rawValue["controlIQTotalDailyInsulin"] as? Int
        alertSnoozeEnabled = rawValue["alertSnoozeEnabled"] as? Bool ?? false
        alertSnoozeDuration = rawValue["alertSnoozeDuration"] as? TimeInterval ?? .minutes(10)
        notificationCount = rawValue["notificationCount"] as? Int
        issuedAlertIdentifiers = Set(rawValue["issuedAlertIdentifiers"] as? [String] ?? [])
        forwardCGMAlerts = rawValue["forwardCGMAlerts"] as? Bool ?? false
        currentPumpTime = rawValue["currentPumpTime"] as? Date
        lastPumpTimeCheckDate = rawValue["lastPumpTimeCheckDate"] as? Date

        if let pumpStateRaw = rawValue["pumpState"] as? PumpState.RawValue {
            pumpState = PumpState(rawValue: pumpStateRaw)
        } else {
            pumpState = PumpState()
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

        if let flagsRaw = rawValue["featureFlags"] as? TandemFeatureFlags.RawValue,
           let decodedFlags = TandemFeatureFlags(rawValue: flagsRaw)
        {
            featureFlags = decodedFlags
        } else {
            featureFlags = .default
        }

        if let reservoirRaw = rawValue["lastReservoirReading"] as? [String: Any] {
            lastReservoirReading = TandemPumpManagerState.decodeReservoirValue(from: reservoirRaw)
        } else {
            lastReservoirReading = nil
        }

        lastReservoirReadingNeedsReport = rawValue["lastReservoirReadingNeedsReport"] as? Bool ?? false

        if let batteryRaw = rawValue["lastBatteryReading"] as? [String: Any] {
            lastBatteryReading = TandemPumpManagerState.decodeBatteryReading(from: batteryRaw)
        } else {
            lastBatteryReading = nil
        }

        if let lastBasalDateInterval = rawValue["lastBasalStatusDate"] as? TimeInterval {
            lastBasalStatusDate = Date(timeIntervalSinceReferenceDate: lastBasalDateInterval)
        } else {
            lastBasalStatusDate = nil
        }

        if let historyBackfillRaw = rawValue["historyBackfill"] as? HistoryBackfillState.RawValue {
            historyBackfill = HistoryBackfillState(rawValue: historyBackfillRaw)
        } else {
            historyBackfill = nil
        }

        if let bolusDoseRaw = rawValue["bolusDose"] as? UnfinalizedDose.RawValue {
            bolusDose = UnfinalizedDose(rawValue: bolusDoseRaw)
        } else {
            bolusDose = nil
        }

        if let pendingRaw = rawValue["pendingBolusFinalization"] as? UnfinalizedDose.RawValue {
            pendingBolusFinalization = UnfinalizedDose(rawValue: pendingRaw)
        } else {
            pendingBolusFinalization = nil
        }

        pumpDiscrepancyCount = rawValue["pumpDiscrepancyCount"] as? Int ?? 0
        if let discrepancyRaw = rawValue["lastPumpDiscrepancy"] as? PumpDiscrepancy.RawValue {
            lastPumpDiscrepancy = PumpDiscrepancy(rawValue: discrepancyRaw)
        } else {
            lastPumpDiscrepancy = nil
        }

        if let bolusRaw = rawValue["bolusState"] as? [String: Any],
           let decodedBolusState = TandemPumpManagerState.decodeBolusState(from: bolusRaw)
        {
            bolusState = decodedBolusState
        } else {
            bolusState = .noBolus
        }

        if let rawInsulinType = rawValue["insulinType"] as? InsulinType.RawValue {
            insulinType = InsulinType(rawValue: rawInsulinType)
        } else {
            insulinType = nil
        }

        if let scheduleRaw = rawValue["basalRateSchedule"] as? [String: Any] {
            basalRateSchedule = TandemPumpManagerState
                .decodeBasalSchedule(from: scheduleRaw) ??
                BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 0)])!
        } else {
            basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 0)])!
        }

        if let rawDoseEntry = rawValue["basalDose"] as? UnfinalizedDose.RawValue {
            basalDose = UnfinalizedDose(rawValue: rawDoseEntry) ?? UnfinalizedDose
                .defaultBasalDose(basalSchedule: basalRateSchedule, insulineType: insulinType)
        } else {
            basalDose = UnfinalizedDose.defaultBasalDose(basalSchedule: basalRateSchedule, insulineType: insulinType)
        }

        if let modeRaw = rawValue["controlIQUserMode"] as? Int {
            controlIQUserMode = ControlIQUserMode(rawValue: modeRaw)
        } else {
            controlIQUserMode = nil
        }

        if let quickBolusAnnunRaw = rawValue["quickBolusAnnun"] as? Int {
            quickBolusAnnun = PumpGlobalsResponse.AnnunciationEnum(rawValue: quickBolusAnnunRaw)
        } else {
            quickBolusAnnun = nil
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

        if let generalAnnunRaw = rawValue["generalAnnun"] as? Int {
            generalAnnun = PumpGlobalsResponse.AnnunciationEnum(rawValue: generalAnnunRaw)
        } else {
            generalAnnun = nil
        }

        quickBolusEnabled = rawValue["quickBolusEnabled"] as? Bool
        quickBolusEntryType = rawValue["quickBolusEntryType"] as? Int
        quickBolusIncrementUnits = rawValue["quickBolusIncrementUnits"] as? Int
        quickBolusIncrementCarbs = rawValue["quickBolusIncrementCarbs"] as? Int
        quickBolusStatus = rawValue["quickBolusStatus"] as? Int
        maxBasalLimitMilliunits = rawValue["maxBasalLimitMilliunits"] as? Int
        maxBasalLimitDefaultMilliunits = rawValue["maxBasalLimitDefaultMilliunits"] as? Int
        maxBolusLimitMilliunits = rawValue["maxBolusLimitMilliunits"] as? Int
        maxBolusLimitDefaultMilliunits = rawValue["maxBolusLimitDefaultMilliunits"] as? Int

        if let lastControlIQInterval = rawValue["lastControlIQUpdate"] as? TimeInterval {
            lastControlIQUpdate = Date(timeIntervalSinceReferenceDate: lastControlIQInterval)
        } else {
            lastControlIQUpdate = nil
        }

        if let cgmSessionStateRaw = rawValue["cgmSessionState"] as? Int {
            cgmSessionState = CGMStatusV2Response.SessionState(rawValue: cgmSessionStateRaw)
        } else {
            cgmSessionState = nil
        }

        if let lastCGMStatusInterval = rawValue["lastCGMStatusUpdate"] as? TimeInterval {
            lastCGMStatusUpdate = Date(timeIntervalSinceReferenceDate: lastCGMStatusInterval)
        } else {
            lastCGMStatusUpdate = nil
        }

        if let lastNotificationInterval = rawValue["lastNotificationUpdate"] as? TimeInterval {
            lastNotificationUpdate = Date(timeIntervalSinceReferenceDate: lastNotificationInterval)
        } else {
            lastNotificationUpdate = nil
        }

        lastSiteChangeDate = rawValue["lastSiteChangeDate"] as? Date
        lastCartridgeChangeDate = rawValue["lastCartridgeChangeDate"] as? Date
        lastCannulaFillAmount = rawValue["lastCannulaFillAmount"] as? Double

        if let rawInsulinType = rawValue["insulinType"] as? InsulinType.RawValue {
            insulinType = InsulinType(rawValue: rawInsulinType)
        } else {
            insulinType = nil
        }
    }

    public var rawValue: RawValue {
        var raw: RawValue = [:]

        raw["onboarded"] = onboarded
        raw["pumpState"] = pumpState.rawValue
        raw["lastReconciliation"] = lastReconciliation?.timeIntervalSinceReferenceDate
        raw["latestInsulinOnBoard"] = latestInsulinOnBoard
        raw["autoAcknowledgeBasalAlerts"] = autoAcknowledgeBasalAlerts
        raw["currentPumpTime"] = currentPumpTime
        raw["lastPumpTimeCheckDate"] = lastPumpTimeCheckDate
        raw["quickBolusAnnun"] = quickBolusAnnun?.rawValue
        raw["reminderAnnun"] = reminderAnnun?.rawValue
        raw["alertAnnun"] = alertAnnun?.rawValue
        raw["alarmAnnun"] = alarmAnnun?.rawValue
        raw["generalAnnun"] = generalAnnun?.rawValue
        raw["quickBolusEnabled"] = quickBolusEnabled
        raw["quickBolusEntryType"] = quickBolusEntryType
        raw["quickBolusIncrementUnits"] = quickBolusIncrementUnits
        raw["quickBolusIncrementCarbs"] = quickBolusIncrementCarbs
        raw["quickBolusStatus"] = quickBolusStatus
        raw["maxBasalLimitMilliunits"] = maxBasalLimitMilliunits
        raw["maxBasalLimitDefaultMilliunits"] = maxBasalLimitDefaultMilliunits
        raw["maxBolusLimitMilliunits"] = maxBolusLimitMilliunits
        raw["maxBolusLimitDefaultMilliunits"] = maxBolusLimitDefaultMilliunits
        raw["useControlIQ"] = useControlIQ
        raw["pendingEnableClosedLoop"] = pendingEnableClosedLoop
        raw["basalDose"] = basalDose.rawValue
        raw["controlIQEnabled"] = controlIQEnabled
        raw["controlIQUserMode"] = controlIQUserMode?.rawValue
        raw["controlIQWeightLbs"] = controlIQWeightLbs
        raw["controlIQWeightUnit"] = controlIQWeightUnit?.rawValue
        raw["controlIQTotalDailyInsulin"] = controlIQTotalDailyInsulin
        raw["lastControlIQUpdate"] = lastControlIQUpdate?.timeIntervalSinceReferenceDate
        raw["cgmSessionState"] = cgmSessionState?.rawValue
        raw["lastCGMStatusUpdate"] = lastCGMStatusUpdate?.timeIntervalSinceReferenceDate
        raw["alertSnoozeEnabled"] = alertSnoozeEnabled
        raw["alertSnoozeDuration"] = alertSnoozeDuration
        raw["notificationCount"] = notificationCount
        raw["lastNotificationUpdate"] = lastNotificationUpdate?.timeIntervalSinceReferenceDate
        raw["issuedAlertIdentifiers"] = Array(issuedAlertIdentifiers).sorted()
        raw["forwardCGMAlerts"] = forwardCGMAlerts
        raw["lastSiteChangeDate"] = lastSiteChangeDate
        raw["lastCartridgeChangeDate"] = lastCartridgeChangeDate
        raw["lastCannulaFillAmount"] = lastCannulaFillAmount
        raw["insulinType"] = insulinType?.rawValue
        raw["useSilentTones"] = useSilentTones
        raw["basalRateSchedule"] = TandemPumpManagerState.encodeBasalSchedule(basalRateSchedule)

        let settingsRaw = settings.rawValue
        if !settingsRaw.isEmpty {
            raw["settings"] = settingsRaw
        }

        // Only explicit choices are stored, so an untouched install follows the defaults.
        let featureFlagsRaw = featureFlags.rawValue
        if !featureFlagsRaw.isEmpty {
            raw["featureFlags"] = featureFlagsRaw
        }

        if let lastReservoirReading = lastReservoirReading {
            raw["lastReservoirReading"] = TandemPumpManagerState.encodeReservoirValue(lastReservoirReading)
        }

        if lastReservoirReadingNeedsReport {
            raw["lastReservoirReadingNeedsReport"] = true
        }

        if let lastBatteryReading = lastBatteryReading {
            raw["lastBatteryReading"] = TandemPumpManagerState.encodeBatteryReading(lastBatteryReading)
        }

        if let lastBasalStatusDate = lastBasalStatusDate {
            raw["lastBasalStatusDate"] = lastBasalStatusDate.timeIntervalSinceReferenceDate
        }

        if let historyBackfill {
            raw["historyBackfill"] = historyBackfill.rawValue
        }

        if let encodedBolusState = TandemPumpManagerState.encodeBolusState(bolusState) {
            raw["bolusState"] = encodedBolusState
        }

        if let bolusDose {
            raw["bolusDose"] = bolusDose.rawValue
        }

        if let pendingBolusFinalization {
            raw["pendingBolusFinalization"] = pendingBolusFinalization.rawValue
        }

        raw["pumpDiscrepancyCount"] = pumpDiscrepancyCount
        if let lastPumpDiscrepancy {
            raw["lastPumpDiscrepancy"] = lastPumpDiscrepancy.rawValue
        }

        return raw
    }

    public var showPumpTimeSyncWarning: Bool {
        guard let currentPumpTime, let lastPumpTimeCheckDate else {
            return false
        }

        // Allow 10s time drift
        return abs(currentPumpTime.timeIntervalSince1970 - lastPumpTimeCheckDate.timeIntervalSince1970) > .seconds(10)
    }

    public var debugDescription: String {
        [
            "### TandemPumpManagerState",
            "* onboarded: \(onboarded)",
            "* pumpState: \(String(describing: pumpState.debugDescription))",
            "* lastReconciliation: \(String(describing: lastReconciliation))",
            "* settings: \(settings)",
            "* featureFlags: \(featureFlags)",
            "* latestInsulinOnBoard: \(String(describing: latestInsulinOnBoard))",
            "* lastReservoirReading: \(String(describing: lastReservoirReading))",
            "* lastReservoirReadingNeedsReport: \(lastReservoirReadingNeedsReport)",
            "* lastBatteryReading: \(String(describing: lastBatteryReading))",
            "* lastBasalStatusDate: \(String(describing: lastBasalStatusDate))",
            "* historyBackfill: \(String(describing: historyBackfill))",
            "* bolusState: \(bolusState)",
            "* pumpDiscrepancyCount: \(pumpDiscrepancyCount)",
            "* lastPumpDiscrepancy: \(String(describing: lastPumpDiscrepancy))",
            "* basalRateSchedule: \(String(describing: basalRateSchedule))",
            "* autoAcknowledgeBasalAlerts: \(autoAcknowledgeBasalAlerts)",
            "* useSilentTones: \(useSilentTones)",
            "* currentPumpTime: \(String(describing: currentPumpTime))",
            "* lastPumpTimeCheckDate: \(String(describing: lastPumpTimeCheckDate))",
            "* quickBolusAnnun: \(String(describing: quickBolusAnnun))",
            "* reminderAnnun: \(String(describing: reminderAnnun))",
            "* alertAnnun: \(String(describing: alertAnnun))",
            "* alarmAnnun: \(String(describing: alarmAnnun))",
            "* generalAnnun: \(String(describing: generalAnnun))",
            "* useControlIQ: \(useControlIQ)",
            "* pendingEnableClosedLoop: \(pendingEnableClosedLoop)",
            "* controlIQEnabled: \(String(describing: controlIQEnabled))",
            "* controlIQUserMode: \(String(describing: controlIQUserMode))",
            "* controlIQWeightLbs: \(String(describing: controlIQWeightLbs))",
            "* controlIQWeightUnit: \(String(describing: controlIQWeightUnit))",
            "* controlIQTotalDailyInsulin: \(String(describing: controlIQTotalDailyInsulin))",
            "* lastControlIQUpdate: \(String(describing: lastControlIQUpdate))",
            "* cgmSessionState: \(String(describing: cgmSessionState))",
            "* lastCGMStatusUpdate: \(String(describing: lastCGMStatusUpdate))",
            "* notificationCount: \(String(describing: notificationCount))",
            "* lastNotificationUpdate: \(String(describing: lastNotificationUpdate))",
            "* issuedAlertIdentifiers: \(issuedAlertIdentifiers.sorted())",
            "* forwardCGMAlerts: \(forwardCGMAlerts)",
            "* lastSiteChangeDate: \(String(describing: lastSiteChangeDate))",
            "* lastCartridgeChangeDate: \(String(describing: lastCartridgeChangeDate))",
            "* lastCannulaFillAmount: \(String(describing: lastCannulaFillAmount))",
            "* quickBolusEnabled: \(String(describing: quickBolusEnabled))",
            "* quickBolusEntryType: \(String(describing: quickBolusEntryType))",
            "* quickBolusIncrementUnits: \(String(describing: quickBolusIncrementUnits))",
            "* quickBolusIncrementCarbs: \(String(describing: quickBolusIncrementCarbs))",
            "* maxBasalLimitMilliunits: \(String(describing: maxBasalLimitMilliunits))",
            "* maxBolusLimitMilliunits: \(String(describing: maxBolusLimitMilliunits))"
        ].joined(separator: "\n")
    }

    public var basalDeliveryState: PumpManagerStatus.BasalDeliveryState {
        switch basalDose.type {
        case .basal,
             .bolus,
             .resume:
            return .active(basalDose.startDate)
        case .suspend:
            return .suspended(basalDose.startDate)
        case .tempBasal:
            return .tempBasal(basalDose.toDoseEntry(isMutable: true))
        }
    }

    public var deviceInfo: HKDevice {
        HKDevice(
            name: "TandemPump",
            manufacturer: "Tandem",
            model: "Mobi",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: nil,
            udiDeviceIdentifier: nil
        )
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
            "chargeRemaining": reading.chargeRemaining,
            "isCharging": reading.isCharging
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
            chargeRemaining: chargeRemaining,
            // Absent in state saved before charging was tracked.
            isCharging: raw["isCharging"] as? Bool ?? false
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

    static func encodeBasalSchedule(_ schedule: BasalRateSchedule) -> [String: Any] {
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
}
