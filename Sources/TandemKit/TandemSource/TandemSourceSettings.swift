import Foundation

/// The optional reads are the sections the Mobi app leaves out when the pump doesn't answer.
struct TandemSourceSettingsReads {
    var globals: PumpGlobalsResponse
    var reminders: RemindersResponse
    var pumpSettings: PumpSettingsResponse
    var glucoseAlerts: CGMGlucoseAlertSettingsResponse
    var rateAlerts: CGMRateAlertSettingsResponse
    var outOfRangeAlert: CGMOORAlertSettingsResponse
    var cgmHardware: CGMHardwareInfoResponse
    var profileStatus: ProfileStatusResponse
    var profiles: [(settings: IDPSettingsResponse, segments: [IDPSegmentResponse])]
    var basalLimit: BasalLimitSettingsResponse?
    var globalMaxBolus: GlobalMaxBolusSettingsResponse?
    var controlIQ: ControlIQInfoV2Response?
    var sleepSchedule: ControlIQSleepScheduleResponse?
    var localization: LocalizationResponse?
}

/// The settings JSON of a Mobi upload, keyed as the iOS app keys it: raw pump values, masked and
/// clamped as the app's models keep them. Snooze is left out; no captured vector backs that read.
struct TandemSourceSettings: Encodable, Equatable {
    let globals: Globals
    let reminders: Reminders
    let pumpSettings: PumpSettingsDetail
    let cgmSettings: CgmSettings
    let profiles: Profiles
    let basalLimitSettings: BasalLimit?
    let globalMaxBolusSettings: GlobalMaxBolus?
    let controlIQSettings: ControlIQ?
    let localizationSettings: Localization?

    /// Sorted keys at every level, as the iOS app's settings JSON is.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    init(_ reads: TandemSourceSettingsReads) {
        globals = Globals(reads.globals)
        reminders = Reminders(reads.reminders)
        pumpSettings = PumpSettingsDetail(reads.pumpSettings)
        cgmSettings = CgmSettings(reads.glucoseAlerts, reads.rateAlerts, reads.outOfRangeAlert, reads.cgmHardware)
        profiles = Profiles(status: reads.profileStatus, profiles: reads.profiles)
        basalLimitSettings = reads.basalLimit.map { BasalLimit(basalLimit: Int($0.basalLimit), basalLimitDefault: Int($0.basalLimitDefault)) }
        globalMaxBolusSettings = reads.globalMaxBolus.map { GlobalMaxBolus(maxBolus: $0.maxBolus, maxBolusDefault: $0.maxBolusDefault) }
        controlIQSettings = reads.controlIQ.map { ControlIQ($0, reads.sleepSchedule) }
        localizationSettings = reads.localization.map(Localization.init)
    }

    /// The app sends its enum's ordinal, which is the raw value in range and its catch-all outside.
    static func ordinal(_ raw: Int, validUpTo max: Int, otherwise fallback: Int) -> Int {
        (0 ... max).contains(raw) ? raw : fallback
    }

    struct Globals: Encodable, Equatable {
        let quickBolusSettings: QuickBolus
        let volumeSettings: Volume

        init(_ r: PumpGlobalsResponse) {
            quickBolusSettings = QuickBolus(
                enabled: r.quickBolusEnabledRaw != 0 ? 1 : 0,
                entryType: TandemSourceSettings.ordinal(r.quickBolusEntryType, validUpTo: 1, otherwise: 0),
                incrementCarbs: r.quickBolusIncrementCarbs,
                incrementUnits: r.quickBolusIncrementUnits,
                status: r.quickBolusStatus & 0x0F
            )
            let annun = { TandemSourceSettings.ordinal($0, validUpTo: 3, otherwise: 4) }
            volumeSettings = Volume(
                alarmAnnun: annun(r.alarmAnnun),
                alertAnnun: annun(r.alertAnnun),
                bolusAnnun: annun(r.generalAnnun),
                buttonAnnun: annun(r.buttonAnnun),
                fillTubingAnnun: annun(r.fillTubingAnnun),
                quickBolusAnnun: annun(r.quickBolusAnnun),
                reminderAnnun: annun(r.reminderAnnun)
            )
        }

        struct QuickBolus: Encodable, Equatable {
            let enabled, entryType, incrementCarbs, incrementUnits, status: Int
        }

        struct Volume: Encodable, Equatable {
            let alarmAnnun, alertAnnun, bolusAnnun, buttonAnnun, fillTubingAnnun, quickBolusAnnun, reminderAnnun: Int
        }
    }

    struct Reminders: Encodable, Equatable {
        let lowBGReminder, highBGReminder, siteChangeReminder, afterBolusReminder, additionalBolusReminder: Reminder
        let missedBolusReminder: [Reminder]
        let lowBGThreshold, highBGThreshold, siteChangeDays, status: Int

        init(_ r: RemindersResponse) {
            lowBGReminder = Reminder(r.lowBGReminder)
            highBGReminder = Reminder(r.highBGReminder)
            siteChangeReminder = Reminder(r.siteChangeReminder)
            missedBolusReminder = [r.missedBolusReminder0, r.missedBolusReminder1, r.missedBolusReminder2, r.missedBolusReminder3].map(Reminder.init)
            afterBolusReminder = Reminder(r.afterBolusReminder)
            additionalBolusReminder = Reminder(r.additionalBolusReminder)
            lowBGThreshold = r.lowBGThreshold
            highBGThreshold = r.highBGThreshold
            siteChangeDays = r.siteChangeDays
            status = r.status & 0x07
        }

        struct Reminder: Encodable, Equatable {
            let activeDays, enabled, endTimeMinutes, frequencyMinutes, startTimeMinutes, status: Int

            init(_ r: RemindersResponse.Reminder) {
                activeDays = Int(r.activeDays) & 0x7F
                enabled = r.enabled != 0 ? 1 : 0
                endTimeMinutes = Int(r.endTime)
                frequencyMinutes = Int(r.frequency)
                startTimeMinutes = Int(r.startTime)
                status = Int(r.validityStatus) & 0x1F
            }
        }
    }

    struct PumpSettingsDetail: Encodable, Equatable {
        let autoShutdownDuration, autoShutdownEnabled, cannulaPrimeSize, featureLock, lowInsulinThreshold, oledTimeout, status: Int

        init(_ r: PumpSettingsResponse) {
            autoShutdownDuration = r.autoShutdownDuration
            autoShutdownEnabled = r.autoShutdownEnabled != 0 ? 1 : 0
            cannulaPrimeSize = r.cannulaPrimeSize
            featureLock = r.featureLock != 0 ? 1 : 0
            lowInsulinThreshold = r.lowInsulinThreshold
            oledTimeout = r.oledTimeout
            status = r.status & 0x5F
        }
    }

    struct CgmSettings: Encodable, Equatable {
        let annunProfile: Int
        let fallRateAlertDefaultBitmask, fallRateAlertEnabled, fallRateAlertLevel: Int
        let highGlucoseAlertDefaultBitmask, highGlucoseAlertDurationMins, highGlucoseAlertEnabled, highGlucoseAlertMgPerDl: Int
        let lowGlucoseAlertDefaultBitmask, lowGlucoseAlertDurationMins, lowGlucoseAlertEnabled, lowGlucoseAlertMgPerDl: Int
        let riseRateAlertDefaultBitmask, riseRateAlertEnabled, riseRateAlertLevel: Int
        let sensorTimeoutDefaultBitmask, sensorTimeoutEnabled, sensorTimeoutMins: Int
        let transmitterID: String

        /// What the app sends when no transmitter id is set.
        static let defaultTransmitterId = "000001"

        init(
            _ g: CGMGlucoseAlertSettingsResponse,
            _ r: CGMRateAlertSettingsResponse,
            _ o: CGMOORAlertSettingsResponse,
            _ h: CGMHardwareInfoResponse
        ) {
            annunProfile = TandemSourceSettings.ordinal(h.lastByte, validUpTo: 3, otherwise: 4)
            fallRateAlertDefaultBitmask = r.fallRateDefaultBitmask & 0x07
            fallRateAlertEnabled = r.fallRateEnabled != 0 ? 1 : 0
            fallRateAlertLevel = r.fallRateThreshold
            highGlucoseAlertDefaultBitmask = g.highGlucoseAlertDefaultBitmask & 0x07
            highGlucoseAlertDurationMins = g.highGlucoseRepeatDuration
            highGlucoseAlertEnabled = g.highGlucoseAlertEnabled != 0 ? 1 : 0
            highGlucoseAlertMgPerDl = g.highGlucoseAlertThreshold
            lowGlucoseAlertDefaultBitmask = g.lowGlucoseAlertDefaultBitmask & 0x07
            lowGlucoseAlertDurationMins = g.lowGlucoseRepeatDuration
            lowGlucoseAlertEnabled = g.lowGlucoseAlertEnabled != 0 ? 1 : 0
            lowGlucoseAlertMgPerDl = g.lowGlucoseAlertThreshold
            riseRateAlertDefaultBitmask = r.riseRateDefaultBitmask & 0x07
            riseRateAlertEnabled = r.riseRateEnabled != 0 ? 1 : 0
            riseRateAlertLevel = r.riseRateThreshold
            sensorTimeoutDefaultBitmask = o.sensorTimeoutDefaultBitmask & 0x07
            sensorTimeoutEnabled = o.sensorTimeoutAlertEnabled != 0 ? 1 : 0
            sensorTimeoutMins = o.sensorTimeoutAlertThreshold
            let id = h.hardwareInfoString.trimmingCharacters(in: .controlCharacters)
            transmitterID = id.isEmpty ? Self.defaultTransmitterId : id
        }
    }

    struct Profiles: Encodable, Equatable {
        let activeIdp, activeSegment, numberOfProfiles: Int
        let profile: [Profile]

        init(status: ProfileStatusResponse, profiles: [(settings: IDPSettingsResponse, segments: [IDPSegmentResponse])]) {
            let active = profiles.first { $0.settings.idpId == status.activeIdpSlotId }
            activeIdp = active?.settings.idpId ?? -1
            activeSegment = active == nil ? -1 : status.activeSegmentIndex
            numberOfProfiles = profiles.count
            profile = profiles.map { Profile(settings: $0.settings, segments: $0.segments) }
        }

        struct Profile: Encodable, Equatable {
            let carbEntry, idp, insulinDuration, maxBolus: Int
            let name: String
            let tDependentNum: Int
            let tDependentSegs: [Segment]

            init(settings: IDPSettingsResponse, segments: [IDPSegmentResponse]) {
                carbEntry = settings.carbEntry ? 1 : 0
                idp = settings.idpId
                insulinDuration = settings.insulinDuration
                maxBolus = settings.maxBolus
                name = settings.name
                tDependentNum = settings.numberOfProfileSegments
                tDependentSegs = segments.sorted { $0.segmentIndex < $1.segmentIndex }.map(Segment.init)
            }
        }

        struct Segment: Encodable, Equatable {
            let basalRate, carbRatio, index, isf, startTime, status, targetBG: Int

            init(_ s: IDPSegmentResponse) {
                basalRate = s.profileBasalRate
                carbRatio = Int(s.profileCarbRatio)
                index = s.segmentIndex
                isf = s.profileISF
                startTime = s.profileStartTime
                status = Self.appStatus(s.idpStatusId)
                targetBG = s.profileTargetBG
            }

            /// The app's parse reads bit 5 and its serialize writes it as bit 4, dropping the pump's bit 4;
            /// the cloud has only ever received that form.
            static func appStatus(_ raw: Int) -> Int {
                (raw & 0x0F) | (raw & 0x20 != 0 ? 0x10 : 0)
            }
        }
    }

    struct BasalLimit: Encodable, Equatable {
        let basalLimit, basalLimitDefault: Int
    }

    struct GlobalMaxBolus: Encodable, Equatable {
        let maxBolus, maxBolusDefault: Int
    }

    struct ControlIQ: Encodable, Equatable {
        let closedLoop, weight, weightUnit, totalDailyInsulin: Int
        let sleepSchedule0, sleepSchedule1, sleepSchedule2, sleepSchedule3: SleepSchedule

        enum CodingKeys: String, CodingKey {
            case closedLoop = "ClosedLoop"
            case weight = "Weight"
            case weightUnit = "WeightUnit"
            case totalDailyInsulin = "TotalDailyInsulin"
            case sleepSchedule0 = "SleepSchedule0"
            case sleepSchedule1 = "SleepSchedule1"
            case sleepSchedule2 = "SleepSchedule2"
            case sleepSchedule3 = "SleepSchedule3"
        }

        init(_ info: ControlIQInfoV2Response, _ sleep: ControlIQSleepScheduleResponse?) {
            closedLoop = info.closedLoopEnabled ? 1 : 0
            weight = info.weight
            weightUnit = TandemSourceSettings.ordinal(info.weightUnitRaw, validUpTo: 2, otherwise: 3)
            totalDailyInsulin = info.totalDailyInsulin
            let read = (sleep?.schedules ?? []).map(SleepSchedule.init)
            let schedules = (0 ..< 4).map { $0 < read.count ? read[$0] : SleepSchedule.empty }
            sleepSchedule0 = schedules[0]
            sleepSchedule1 = schedules[1]
            sleepSchedule2 = schedules[2]
            sleepSchedule3 = schedules[3]
        }

        struct SleepSchedule: Encodable, Equatable {
            let activeDays, enabled, endTime, startTime: Int

            static let empty = SleepSchedule(activeDays: 0, enabled: 0, endTime: 0, startTime: 0)

            enum CodingKeys: String, CodingKey {
                case activeDays = "ActiveDays"
                case enabled = "Enabled"
                case endTime = "EndTime"
                case startTime = "StartTime"
            }

            init(activeDays: Int, enabled: Int, endTime: Int, startTime: Int) {
                self.activeDays = activeDays
                self.enabled = enabled
                self.endTime = endTime
                self.startTime = startTime
            }

            init(_ s: ControlIQSleepScheduleResponse.SleepSchedule) {
                self.init(activeDays: s.activeDays & 0x7F, enabled: s.enabled != 0 ? 1 : 0, endTime: s.endTime, startTime: s.startTime)
            }
        }
    }

    struct Localization: Encodable, Equatable {
        let glucoseUOM, languageSelected, regionSelected: Int

        init(_ r: LocalizationResponse) {
            glucoseUOM = TandemSourceSettings.ordinal(r.glucoseUOM, validUpTo: 1, otherwise: 2)
            languageSelected = r.languageSelected == 255 ? 13 : TandemSourceSettings.ordinal(r.languageSelected, validUpTo: 12, otherwise: 14)
            regionSelected = TandemSourceSettings.ordinal(r.regionSetting, validUpTo: 2, otherwise: 3)
        }
    }
}
