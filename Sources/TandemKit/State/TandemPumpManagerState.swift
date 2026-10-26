import Foundation
import HealthKit
import LoopKit

public struct TandemPumpManagerState: RawRepresentable, Equatable, CustomDebugStringConvertible {
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
    /// The pump's own IOB in units, as its screen shows it: bolus insulin only, or under
    /// Control-IQ basal above and below the profile too. Nothing doses on it.
    public var latestInsulinOnBoard: Double?
    public var pumpInsulinDuration: PumpInsulinDuration?
    public var lastReservoirReading: ReservoirValue?
    /// Cleared once `lastReservoirReading` has reached the delegate, which waits for one to attach and
    /// for `lastReconciliation` to cover the reading. Persisted so a held reading survives a relaunch.
    public var lastReservoirReadingNeedsReport: Bool = false
    public var lastBatteryReading: BatteryReading?
    public var lastBasalStatusDate: Date?
    /// When the pump's basal rate was first seen to differ from the schedule, since when the driver
    /// has been writing the schedule to the pump. Cleared once the pump's profile is read back
    /// matching. Persisted so relaunches don't restart `basalProfileUpdateTimeout`.
    public var basalRateMismatchDetectedAt: Date?
    /// Set once a mismatch outlives `basalProfileUpdateTimeout`; temp basals are refused until a
    /// matching read-back clears it.
    public var basalProfileUpdateFailed = false
    /// How far the driver has read this pump's history log, and the earliest date it may report
    /// events for. Persisted so a relaunch resumes an incremental read instead of re-walking the
    /// pump's whole history into an empty session store.
    public var historyBackfill: HistoryBackfillState?
    public var bolusReportLedger = BolusReportLedger(trackingSince: Date())
    public var reportedBasal = ReportedBasalLedger(trackingSince: Date())
    /// The last temp basal `raw` minted from the pump's `tempRateId`; see `tempBasalEventRaw`.
    public var lastTempRateEventRaw: Data?
    /// The last bolus `raw` minted from the pump's `bolusId`; see `bolusEventRaw`.
    public var lastBolusEventRaw: Data?
    public var deliveryTransitions = DeliveryTransitionLedger()
    public var bolusState: PumpManagerStatus.BolusState = .noBolus
    public var insulinType: InsulinType?
    public var bolusDose: UnfinalizedDose?
    public var pendingBolusFinalization: UnfinalizedDose?
    public var basalDose: UnfinalizedDose
    public var basalRateSchedule: BasalRateSchedule
    /// Set by the first successful `syncBasalRateSchedule`; until then the pump's profile may not
    /// be the app's, and a temp rate (a percent of that profile) would deliver an unknown rate.
    public var hasSyncedBasalRateSchedule: Bool = false
    /// Basal min/max alerts are auto-acknowledged unconditionally: oref routinely sets a zero
    /// basal rate, which the pump would otherwise announce with a notification every time. Kept as
    /// state rather than a constant so tests can exercise the disabled path, but there is no
    /// user-facing way to turn it off.
    public var autoAcknowledgeBasalAlerts: Bool = true
    public var useSilentTones: Bool = false

    // Pump time
    public var currentPumpTime: Date?
    public var lastPumpTimeCheckDate: Date?
    /// The phone's UTC offset in seconds when `currentPumpTime` was decoded.
    public var pumpTimeCheckUTCOffset: Int?

    // Pump global settings
    /// In memory only, not saved with the state, so a relaunch re-reads the pump's settings at its first sync.
    public var lastSettingsCheckedAt: Date?
    public var quickBolusAnnun: PumpGlobalsResponse.AnnunciationEnum?
    public var reminderAnnun: PumpGlobalsResponse.AnnunciationEnum?
    public var alertAnnun: PumpGlobalsResponse.AnnunciationEnum?
    public var alarmAnnun: PumpGlobalsResponse.AnnunciationEnum?
    public var generalAnnun: PumpGlobalsResponse.AnnunciationEnum?
    /// Set by the onboarding sound screen: the `*Annun` values are the user's choices, which no
    /// pump-globals read may replace until `applyOnboardingSettings` has tried to write them. In memory only.
    public var pumpSoundsAwaitingWrite = false

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
    /// When `useControlIQ` last went off; cleared once history has reported Control-IQ's basal up to it.
    public var controlIQEndedAt: Date?
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
    /// Persisted, like `issuedAlertIdentifiers`, so a relaunch retracts the alert rather than re-issuing it.
    public var pumpClockSkewAlertIssued = false
    /// `stableIdentifier`s of the alarms and malfunctions reported as `.alarm` pump events and not yet
    /// cleared. Persisted so a relaunch neither reports a standing alarm again nor misses its clearing.
    public var reportedPumpAlarmIdentifiers: Set<String> = []
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
    /// Kept through `deleteSavedPumpState`, unlike `pumpState.pumpSerial`, so pairing another pump
    /// is reported as a replacement.
    public var lastPumpSerial: UInt32?

    public static func == (lhs: TandemPumpManagerState, rhs: TandemPumpManagerState) -> Bool {
        // Not one && chain: that takes the type checker ten times as long, most of a second.
        guard lhs.onboarded == rhs.onboarded,
              lhs.pumpState == rhs.pumpState,
              lhs.isConnected == rhs.isConnected,
              lhs.lastReconciliation == rhs.lastReconciliation,
              lhs.settings == rhs.settings,
              lhs.featureFlags == rhs.featureFlags,
              lhs.latestInsulinOnBoard == rhs.latestInsulinOnBoard,
              lhs.pumpInsulinDuration == rhs.pumpInsulinDuration,
              lhs.lastReservoirReading?.startDate == rhs.lastReservoirReading?.startDate,
              lhs.lastReservoirReading?.unitVolume == rhs.lastReservoirReading?.unitVolume,
              lhs.lastReservoirReadingNeedsReport == rhs.lastReservoirReadingNeedsReport,
              lhs.lastBatteryReading == rhs.lastBatteryReading,
              lhs.lastBasalStatusDate == rhs.lastBasalStatusDate,
              lhs.basalRateMismatchDetectedAt == rhs.basalRateMismatchDetectedAt,
              lhs.basalProfileUpdateFailed == rhs.basalProfileUpdateFailed,
              lhs.historyBackfill == rhs.historyBackfill,
              lhs.bolusReportLedger == rhs.bolusReportLedger,
              lhs.reportedBasal == rhs.reportedBasal,
              lhs.lastTempRateEventRaw == rhs.lastTempRateEventRaw,
              lhs.lastBolusEventRaw == rhs.lastBolusEventRaw,
              lhs.deliveryTransitions == rhs.deliveryTransitions,
              lhs.bolusState == rhs.bolusState,
              lhs.insulinType == rhs.insulinType,
              lhs.bolusDose == rhs.bolusDose,
              lhs.pendingBolusFinalization == rhs.pendingBolusFinalization,
              lhs.basalDose == rhs.basalDose,
              lhs.basalRateSchedule == rhs.basalRateSchedule,
              lhs.hasSyncedBasalRateSchedule == rhs.hasSyncedBasalRateSchedule,
              lhs.autoAcknowledgeBasalAlerts == rhs.autoAcknowledgeBasalAlerts,
              lhs.useSilentTones == rhs.useSilentTones,
              lhs.currentPumpTime == rhs.currentPumpTime,
              lhs.lastPumpTimeCheckDate == rhs.lastPumpTimeCheckDate,
              lhs.pumpTimeCheckUTCOffset == rhs.pumpTimeCheckUTCOffset,
              lhs.lastSettingsCheckedAt == rhs.lastSettingsCheckedAt,
              lhs.quickBolusAnnun == rhs.quickBolusAnnun,
              lhs.reminderAnnun == rhs.reminderAnnun,
              lhs.alertAnnun == rhs.alertAnnun,
              lhs.alarmAnnun == rhs.alarmAnnun,
              lhs.generalAnnun == rhs.generalAnnun,
              lhs.pumpSoundsAwaitingWrite == rhs.pumpSoundsAwaitingWrite,
              lhs.quickBolusEnabled == rhs.quickBolusEnabled,
              lhs.quickBolusEntryType == rhs.quickBolusEntryType,
              lhs.quickBolusIncrementUnits == rhs.quickBolusIncrementUnits,
              lhs.quickBolusIncrementCarbs == rhs.quickBolusIncrementCarbs,
              lhs.quickBolusStatus == rhs.quickBolusStatus,
              lhs.maxBasalLimitMilliunits == rhs.maxBasalLimitMilliunits,
              lhs.maxBasalLimitDefaultMilliunits == rhs.maxBasalLimitDefaultMilliunits,
              lhs.maxBolusLimitMilliunits == rhs.maxBolusLimitMilliunits,
              lhs.maxBolusLimitDefaultMilliunits == rhs.maxBolusLimitDefaultMilliunits,
              lhs.useControlIQ == rhs.useControlIQ,
              lhs.controlIQEndedAt == rhs.controlIQEndedAt,
              lhs.pendingEnableClosedLoop == rhs.pendingEnableClosedLoop,
              lhs.controlIQEnabled == rhs.controlIQEnabled,
              lhs.controlIQUserMode == rhs.controlIQUserMode,
              lhs.controlIQWeightLbs == rhs.controlIQWeightLbs,
              lhs.controlIQWeightUnit == rhs.controlIQWeightUnit,
              lhs.controlIQTotalDailyInsulin == rhs.controlIQTotalDailyInsulin,
              lhs.lastControlIQUpdate == rhs.lastControlIQUpdate,
              lhs.cgmSessionState == rhs.cgmSessionState,
              lhs.lastCGMStatusUpdate == rhs.lastCGMStatusUpdate,
              lhs.alertSnoozeEnabled == rhs.alertSnoozeEnabled,
              lhs.alertSnoozeDuration == rhs.alertSnoozeDuration,
              lhs.notificationCount == rhs.notificationCount,
              lhs.lastNotificationUpdate == rhs.lastNotificationUpdate,
              lhs.issuedAlertIdentifiers == rhs.issuedAlertIdentifiers,
              lhs.pumpClockSkewAlertIssued == rhs.pumpClockSkewAlertIssued,
              lhs.reportedPumpAlarmIdentifiers == rhs.reportedPumpAlarmIdentifiers,
              lhs.forwardCGMAlerts == rhs.forwardCGMAlerts,
              lhs.lastSiteChangeDate == rhs.lastSiteChangeDate,
              lhs.lastCartridgeChangeDate == rhs.lastCartridgeChangeDate,
              lhs.lastCannulaFillAmount == rhs.lastCannulaFillAmount,
              lhs.lastPumpSerial == rhs.lastPumpSerial
        else {
            return false
        }
        return true
    }

    public init(
        basalRateSchedule: BasalRateSchedule,
        maxBasalRateUnitsPerHour: Double? = nil,
        maxBolusUnits: Double? = nil
    ) {
        self.basalRateSchedule = basalRateSchedule
        pumpState = PumpState()
        basalDose = .defaultBasalDose(basalSchedule: basalRateSchedule, insulineType: nil)
        settings = TandemPumpManagerSettings(
            maxBolus: maxBolusUnits,
            maxTempBasalRate: maxBasalRateUnitsPerHour,
            maxBasalScheduleEntry: basalRateSchedule.items.map(\.value).max()
        )
    }

    public init(rawValue: RawValue) {
        onboarded = rawValue["onboarded"] as? Bool ?? false
        isConnected = false // To prevent having an old isConnected state
        latestInsulinOnBoard = rawValue["latestInsulinOnBoard"] as? Double
        pumpInsulinDuration = (rawValue["pumpInsulinDuration"] as? PumpInsulinDuration.RawValue)
            .flatMap(PumpInsulinDuration.init(rawValue:))
        useSilentTones = rawValue["useSilentTones"] as? Bool ?? false
        // Intentionally ignores any persisted value: state saved before auto-acknowledge became
        // mandatory may hold `false`, and those pumps should migrate on, not stay off.
        autoAcknowledgeBasalAlerts = true
        useControlIQ = rawValue["useControlIQ"] as? Bool ?? false
        controlIQEndedAt = rawValue["controlIQEndedAt"] as? Date
        hasSyncedBasalRateSchedule = rawValue["hasSyncedBasalRateSchedule"] as? Bool ?? false
        basalRateMismatchDetectedAt = rawValue["basalRateMismatchDetectedAt"] as? Date
        basalProfileUpdateFailed = rawValue["basalProfileUpdateFailed"] as? Bool ?? false
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
        pumpClockSkewAlertIssued = rawValue["pumpClockSkewAlertIssued"] as? Bool ?? false
        reportedPumpAlarmIdentifiers = Set(rawValue["reportedPumpAlarmIdentifiers"] as? [String] ?? [])
        forwardCGMAlerts = rawValue["forwardCGMAlerts"] as? Bool ?? false
        currentPumpTime = rawValue["currentPumpTime"] as? Date
        lastPumpTimeCheckDate = rawValue["lastPumpTimeCheckDate"] as? Date
        pumpTimeCheckUTCOffset = rawValue["pumpTimeCheckUTCOffset"] as? Int

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

        if let ledgerRaw = rawValue["bolusReportLedger"] as? BolusReportLedger.RawValue,
           let ledger = BolusReportLedger(rawValue: ledgerRaw)
        {
            bolusReportLedger = ledger
        }

        if let ledgerRaw = rawValue["reportedBasal"] as? ReportedBasalLedger.RawValue,
           let ledger = ReportedBasalLedger(rawValue: ledgerRaw)
        {
            reportedBasal = ledger
        }
        lastTempRateEventRaw = rawValue["lastTempRateEventRaw"] as? Data
        lastBolusEventRaw = rawValue["lastBolusEventRaw"] as? Data

        if let ledgerRaw = rawValue["deliveryTransitions"] as? DeliveryTransitionLedger.RawValue,
           let ledger = DeliveryTransitionLedger(rawValue: ledgerRaw)
        {
            deliveryTransitions = ledger
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
        lastPumpSerial = rawValue["lastPumpSerial"] as? UInt32 ?? pumpState.pumpSerial

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
        raw["pumpInsulinDuration"] = pumpInsulinDuration?.rawValue
        raw["autoAcknowledgeBasalAlerts"] = autoAcknowledgeBasalAlerts
        raw["currentPumpTime"] = currentPumpTime
        raw["lastPumpTimeCheckDate"] = lastPumpTimeCheckDate
        raw["pumpTimeCheckUTCOffset"] = pumpTimeCheckUTCOffset
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
        raw["controlIQEndedAt"] = controlIQEndedAt
        raw["hasSyncedBasalRateSchedule"] = hasSyncedBasalRateSchedule
        raw["basalRateMismatchDetectedAt"] = basalRateMismatchDetectedAt
        raw["basalProfileUpdateFailed"] = basalProfileUpdateFailed
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
        raw["pumpClockSkewAlertIssued"] = pumpClockSkewAlertIssued
        raw["reportedPumpAlarmIdentifiers"] = Array(reportedPumpAlarmIdentifiers).sorted()
        raw["forwardCGMAlerts"] = forwardCGMAlerts
        raw["lastSiteChangeDate"] = lastSiteChangeDate
        raw["lastCartridgeChangeDate"] = lastCartridgeChangeDate
        raw["lastCannulaFillAmount"] = lastCannulaFillAmount
        raw["lastPumpSerial"] = lastPumpSerial
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

        raw["bolusReportLedger"] = bolusReportLedger.rawValue
        raw["reportedBasal"] = reportedBasal.rawValue
        raw["lastTempRateEventRaw"] = lastTempRateEventRaw
        raw["lastBolusEventRaw"] = lastBolusEventRaw
        raw["deliveryTransitions"] = deliveryTransitions.rawValue

        if let encodedBolusState = TandemPumpManagerState.encodeBolusState(bolusState) {
            raw["bolusState"] = encodedBolusState
        }

        if let bolusDose {
            raw["bolusDose"] = bolusDose.rawValue
        }

        if let pendingBolusFinalization {
            raw["pendingBolusFinalization"] = pendingBolusFinalization.rawValue
        }

        return raw
    }

    /// Seconds the pump's clock is ahead of the phone's (negative if behind), as of the last
    /// `fetchTimeSinceReset`. Pump dates decode with the phone's current UTC offset, so a zone
    /// change since that read moves every one of them, and the offset with them.
    public var pumpClockOffset: TimeInterval {
        guard let currentPumpTime, let lastPumpTimeCheckDate else {
            return 0
        }
        let zoneChange = pumpTimeCheckUTCOffset.map { $0 - TimeZone.current.secondsFromGMT() } ?? 0
        return currentPumpTime.timeIntervalSince(lastPumpTimeCheckDate) + TimeInterval(zoneChange)
    }

    /// Past this the pump's segments sit a host loop cycle or more from the host's, so temp basals
    /// are worked out against the pump's own and the user is told to sync its clock.
    public static let pumpClockSkewThreshold: TimeInterval = .minutes(5)

    /// Past this the clocks differ by more than any time zone or DST change can explain.
    public static let pumpClockOffsetTrustLimit: TimeInterval = .hours(24)

    public static func trustsPumpClockOffset(_ offset: TimeInterval) -> Bool {
        abs(offset) <= pumpClockOffsetTrustLimit
    }

    /// Follows the latest clock read, so it clears as soon as one reads inside the limit.
    public var isPumpClockUntrusted: Bool {
        currentPumpTime != nil && !Self.trustsPumpClockOffset(pumpClockOffset)
    }

    public var isPumpClockSkewed: Bool {
        currentPumpTime != nil && abs(pumpClockOffset) > Self.pumpClockSkewThreshold
    }

    public enum BasalProfileUpdateStatus: Equatable {
        case none
        case updating
        case failed
    }

    public var basalProfileUpdateStatus: BasalProfileUpdateStatus {
        if basalProfileUpdateFailed {
            return .failed
        }
        return basalRateMismatchDetectedAt == nil ? .none : .updating
    }

    public var showPumpTimeSyncWarning: Bool {
        // Allow 10s time drift
        abs(pumpClockOffset) > .seconds(10)
    }

    public var debugDescription: String {
        var lines = ["### TandemPumpManagerState", "* onboarded: \(onboarded)"]
        lines += debugSection("pumpState", pumpState.debugFields)
        lines += [
            "* isConnected: \(isConnected)",
            "* lastReconciliation: \(debugValue(lastReconciliation))"
        ]
        lines += debugSection("settings", [
            "* maxBolus: \(debugValue(settings.maxBolus.map { "\($0) U" }))",
            "* maxTempBasalRate: \(debugValue(settings.maxTempBasalRate.map { "\($0) U/hr" }))",
            "* maxBasalScheduleEntry: \(debugValue(settings.maxBasalScheduleEntry.map { "\($0) U/hr" }))"
        ])
        lines += [
            "* featureFlags: \(featureFlags)",
            "* latestInsulinOnBoard: \(debugValue(latestInsulinOnBoard.map { "\($0) U" }))",
            "* pumpInsulinDuration: \(debugValue(pumpInsulinDuration.map(\.debugDescription)))",
            "* lastReservoirReading: \(debugValue(lastReservoirReading.map { "\($0.unitVolume) U at \($0.startDate)" }))",
            "* lastReservoirReadingNeedsReport: \(lastReservoirReadingNeedsReport)",
            "* lastBatteryReading: \(debugValue(lastBatteryReading.map(\.debugDescription)))",
            "* lastBasalStatusDate: \(debugValue(lastBasalStatusDate))",
            "* basalRateMismatchDetectedAt: \(debugValue(basalRateMismatchDetectedAt))",
            "* basalProfileUpdateFailed: \(basalProfileUpdateFailed)"
        ]
        if let historyBackfill {
            lines += debugSection("historyBackfill", [
                "* pumpSerial: \(historyBackfill.pumpSerial)",
                "* watermark: \(debugValue(historyBackfill.watermark))",
                "* firstSeenFloor: \(debugValue(historyBackfill.firstSeenFloor))"
            ])
        } else {
            lines.append("* historyBackfill: nil")
        }
        lines += debugSection("bolusReportLedger", bolusReportLedger.debugFields)
        lines += debugSection("reportedBasal", reportedBasal.debugFields)
        lines.append("* lastTempRateEventRaw: \(lastTempRateEventRaw?.hexadecimalString ?? "nil")")
        lines.append("* lastBolusEventRaw: \(lastBolusEventRaw?.hexadecimalString ?? "nil")")
        lines += debugSection("deliveryTransitions", deliveryTransitions.debugFields)
        lines += [
            "* bolusState: \(bolusState)",
            "* insulinType: \(debugValue(insulinType))",
            "* bolusDose: \(debugValue(bolusDose?.debugDescription))",
            "* pendingBolusFinalization: \(debugValue(pendingBolusFinalization?.debugDescription))",
            "* basalDose: \(basalDose.debugDescription)",
            "* basalRateSchedule: \(basalRateScheduleDebugSummary)",
            "* hasSyncedBasalRateSchedule: \(hasSyncedBasalRateSchedule)",
            "* autoAcknowledgeBasalAlerts: \(autoAcknowledgeBasalAlerts)",
            "* useSilentTones: \(useSilentTones)",
            "* currentPumpTime: \(debugValue(currentPumpTime))",
            "* lastPumpTimeCheckDate: \(debugValue(lastPumpTimeCheckDate))",
            "* pumpTimeCheckUTCOffset: \(debugValue(pumpTimeCheckUTCOffset.map { "\($0) s" }))",
            "* lastSettingsCheckedAt: \(debugValue(lastSettingsCheckedAt))",
            "* quickBolusAnnun: \(debugValue(quickBolusAnnun))",
            "* reminderAnnun: \(debugValue(reminderAnnun))",
            "* alertAnnun: \(debugValue(alertAnnun))",
            "* alarmAnnun: \(debugValue(alarmAnnun))",
            "* generalAnnun: \(debugValue(generalAnnun))",
            "* pumpSoundsAwaitingWrite: \(pumpSoundsAwaitingWrite)",
            "* quickBolusEnabled: \(debugValue(quickBolusEnabled))",
            "* quickBolusEntryType: \(debugValue(quickBolusEntryType))",
            "* quickBolusIncrementUnits: \(debugValue(quickBolusIncrementUnits))",
            "* quickBolusIncrementCarbs: \(debugValue(quickBolusIncrementCarbs))",
            "* quickBolusStatus: \(debugValue(quickBolusStatus))",
            "* maxBasalLimitMilliunits: \(debugValue(maxBasalLimitMilliunits))",
            "* maxBasalLimitDefaultMilliunits: \(debugValue(maxBasalLimitDefaultMilliunits))",
            "* maxBolusLimitMilliunits: \(debugValue(maxBolusLimitMilliunits))",
            "* maxBolusLimitDefaultMilliunits: \(debugValue(maxBolusLimitDefaultMilliunits))",
            "* useControlIQ: \(useControlIQ)",
            "* controlIQEndedAt: \(debugValue(controlIQEndedAt))",
            "* pendingEnableClosedLoop: \(pendingEnableClosedLoop)",
            "* controlIQEnabled: \(debugValue(controlIQEnabled))",
            "* controlIQUserMode: \(debugValue(controlIQUserMode))",
            "* controlIQWeightLbs: \(debugValue(controlIQWeightLbs))",
            "* controlIQWeightUnit: \(debugValue(controlIQWeightUnit))",
            "* controlIQTotalDailyInsulin: \(debugValue(controlIQTotalDailyInsulin))",
            "* lastControlIQUpdate: \(debugValue(lastControlIQUpdate))",
            "* cgmSessionState: \(debugValue(cgmSessionState))",
            "* lastCGMStatusUpdate: \(debugValue(lastCGMStatusUpdate))",
            "* alertSnoozeEnabled: \(alertSnoozeEnabled)",
            "* alertSnoozeDuration: \(alertSnoozeDuration) s",
            "* notificationCount: \(debugValue(notificationCount))",
            "* lastNotificationUpdate: \(debugValue(lastNotificationUpdate))",
            "* issuedAlertIdentifiers: \(issuedAlertIdentifiers.sorted())",
            "* pumpClockSkewAlertIssued: \(pumpClockSkewAlertIssued)",
            "* reportedPumpAlarmIdentifiers: \(reportedPumpAlarmIdentifiers.sorted())",
            "* forwardCGMAlerts: \(forwardCGMAlerts)",
            "* lastSiteChangeDate: \(debugValue(lastSiteChangeDate))",
            "* lastCartridgeChangeDate: \(debugValue(lastCartridgeChangeDate))",
            "* lastCannulaFillAmount: \(debugValue(lastCannulaFillAmount.map { "\($0) U" }))",
            "* lastPumpSerial: \(debugValue(lastPumpSerial))"
        ]
        return lines.joined(separator: "\n")
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

// MARK: - Debug description

/// `String(describing:)` without the `Optional(...)` around a value that is present.
func debugValue<T>(_ value: T?) -> String {
    value.map { String(describing: $0) } ?? "nil"
}

func debugSection(_ name: String, _ fields: [String]) -> [String] {
    ["* \(name):"] + fields.map { "  " + $0 }
}

/// Ledgers keep a day or more of rows, so a description lists only the latest and the open ones.
private let debugRecentRowCount = 5

private func debugRecentAndOpen<T>(_ rows: [T], isOpen: (T) -> Bool) -> [T] {
    rows.enumerated().filter { $0.offset >= rows.count - debugRecentRowCount || isOpen($0.element) }.map { $0.element }
}

extension TandemPumpManagerState.BatteryReading: CustomDebugStringConvertible {
    public var debugDescription: String {
        "\(Int((chargeRemaining * 100).rounded()))% at \(date)\(isCharging ? ", charging" : "")"
    }
}

extension PumpInsulinDuration: CustomDebugStringConvertible {
    public var debugDescription: String {
        var description = "\(current / 3600) h"
        if let replaced, let replacedAt {
            description += ", replaced \(replaced / 3600) h at \(replacedAt)"
        }
        return description
    }
}

extension TandemPumpManagerState {
    fileprivate var basalRateScheduleDebugSummary: String {
        let items = basalRateSchedule.items.map { item in
            let minutes = Int(item.startTime / 60)
            return String(format: "%02d:%02d", minutes / 60, minutes % 60) + " \(item.value) U/hr"
        }
        return items.joined(separator: ", ") + " (\(basalRateSchedule.timeZone.identifier))"
    }
}

extension BolusReportLedger {
    var debugFields: [String] {
        let unfinalizedCount = entries.filter { !$0.isFinalized }.count
        var fields = [
            "* trackingSince: \(trackingSince)",
            entries.isEmpty
                ? "* entries: none"
                : "* entries: \(entries.count), \(unfinalizedCount) unfinalized; the last \(debugRecentRowCount) and any unfinalized:"
        ]
        fields += debugRecentAndOpen(entries) { !$0.isFinalized }.map { entry in
            var line = "  * bolusId \(entry.bolusId): \(entry.units.map { "\($0) U" } ?? "amount unknown") at \(entry.eventDate)"
            line += ", \(entry.origin) \(entry.part)"
            if entry.automatic { line += ", automatic" }
            if let programmedEndDate = entry.programmedEndDate { line += ", programmed end \(programmedEndDate)" }
            return line + (entry.isFinalized ? ", finalized" : ", unfinalized")
        }
        fields.append(unreported.isEmpty ? "* unreported: none" : "* unreported:")
        fields += unreported.map {
            "  * bolusId \($0.bolusId) started \($0.startDate), holds the boundary at \($0.holdsBoundaryAt)"
        }
        return fields
    }
}

extension ReportedBasalLedger {
    var debugFields: [String] {
        let mutableCount = rows.filter(\.isMutable).count
        var fields = [
            "* trackingSince: \(trackingSince)",
            "* pumpSerial: \(debugValue(pumpSerial))",
            "* reconciledThrough: \(debugValue(reconciledThrough))",
            rows.isEmpty
                ? "* rows: none"
                : "* rows: \(rows.count), \(mutableCount) mutable; the last \(debugRecentRowCount) and any mutable:"
        ]
        fields += debugRecentAndOpen(rows) { $0.isMutable }.map { row in
            var line = "  * \(row.kind)"
            if row.kind == .tempBasal || row.kind == .basal { line += " \(row.rate) U/hr" }
            line += row.end == row.date ? " at \(row.date)" : " \(row.date) to \(row.end)"
            if let tempRateId = row.tempRateId { line += ", tempRateId \(tempRateId)" }
            return line + (row.isMutable ? ", mutable" : "")
        }
        return fields
    }
}

extension DeliveryTransitionLedger {
    var debugFields: [String] {
        var fields = [
            "* pumpSerial: \(debugValue(pumpSerial))",
            "* trackedAfter: \(debugValue(trackedAfter))",
            entries.isEmpty ? "* entries: none" : "* entries:"
        ]
        fields += entries.map { entry in
            var line = "  * \(entry.kind) at \(entry.date), pump record between \(entry.earliest) and \(entry.latest)"
            if let sequenceNum = entry.sequenceNum { line += ", sequenceNum \(sequenceNum)" }
            return line + (entry.isReported ? "" : ", not reported")
        }
        if let pending {
            var line = "* pending: \(pending.observed) detected at \(pending.detectedAt), last confirmed \(pending.lastConfirmed)"
            if let replacement = pending.replacement {
                line += ", replaced by a \(replacement.percent)% temp (\(replacement.rate) U/hr) from \(replacement.start)"
            }
            fields += [line, "  * prior: \(pending.prior.debugDescription)"]
        } else {
            fields.append("* pending: nil")
        }
        fields += [
            "* lastConfirmedObservation: \(debugValue(lastConfirmedObservation))",
            "* interruptedTemp: \(debugValue(interruptedTemp?.debugDescription))"
        ]
        return fields
    }
}
