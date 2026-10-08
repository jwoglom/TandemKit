import Foundation
import LoopKit
@testable import TandemKit
import XCTest

final class TandemPumpManagerStateEqualityTests: XCTestCase {
    private static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testFullyPopulatedStateEqualsACopyOfItself() {
        let state = Self.populatedState()
        let copy = state

        XCTAssertEqual(copy, state)
    }

    func testStatesBuiltSeparatelyFromTheSameValuesAreEqual() {
        XCTAssertEqual(Self.populatedState(), Self.populatedState())
    }

    func testStatesWithoutAReservoirReadingAreEqual() {
        var lhs = Self.populatedState()
        lhs.lastReservoirReading = nil
        var rhs = Self.populatedState()
        rhs.lastReservoirReading = nil

        XCTAssertEqual(lhs, rhs)
    }

    func testChangingAnyStoredPropertyMakesTheStatesUnequal() {
        let base = Self.populatedState()

        for (name, mutate) in Self.mutations {
            var changed = Self.populatedState()
            mutate(&changed)
            XCTAssertFalse(changed == base, "Changing \(name) left the states equal")
        }
    }

    func testEveryStoredPropertyHasAMutation() {
        let stored = Set(Mirror(reflecting: Self.populatedState()).storedPropertyNames)
        let mutated = Set(Self.mutations.map { String($0.name.prefix { $0 != "." }) })

        XCTAssertEqual(stored.subtracting(mutated).sorted(), [], "Add a mutation for each, and compare it in ==")
        XCTAssertEqual(mutated.subtracting(stored).sorted(), [], "Mutations naming no stored property")
    }

    func testRawValueRoundTripRestoresAnEqualState() {
        var state = Self.populatedState()
        // Not persisted: a relaunch starts disconnected, re-reads the pump's settings and restarts an
        // unfinished setup.
        state.isConnected = false
        state.lastSettingsCheckedAt = nil
        state.pumpSoundsAwaitingWrite = false

        XCTAssertEqual(TandemPumpManagerState(rawValue: state.rawValue), state)
    }

    private static var mutations: [(name: String, mutate: (inout TandemPumpManagerState) -> Void)] {
        let later = t0.addingTimeInterval(60)
        return [
            ("onboarded", { $0.onboarded = false }),
            ("pumpState", { $0.pumpState.pumpSerial = 1_234_567 }),
            ("isConnected", { $0.isConnected = false }),
            ("lastReconciliation", { $0.lastReconciliation = nil }),
            ("settings", { $0.settings.maxBolus = 5 }),
            ("featureFlags", { $0.featureFlags[.controlIQSupport] = false }),
            ("latestInsulinOnBoard", { $0.latestInsulinOnBoard = nil }),
            ("lastReservoirReading", { $0.lastReservoirReading = nil }),
            ("lastReservoirReading.startDate", {
                $0.lastReservoirReading = SimpleReservoirValue(startDate: later, unitVolume: 142.5)
            }),
            ("lastReservoirReading.unitVolume", {
                $0.lastReservoirReading = SimpleReservoirValue(startDate: t0, unitVolume: 140)
            }),
            ("lastReservoirReadingNeedsReport", { $0.lastReservoirReadingNeedsReport = false }),
            ("lastBatteryReading", { $0.lastBatteryReading = nil }),
            ("lastBasalStatusDate", { $0.lastBasalStatusDate = nil }),
            ("basalRateMismatchDetectedAt", { $0.basalRateMismatchDetectedAt = nil }),
            ("basalProfileUpdateFailed", { $0.basalProfileUpdateFailed = false }),
            ("historyBackfill", { $0.historyBackfill?.advanceWatermark(through: 5000) }),
            ("bolusReportLedger", { $0.bolusReportLedger.markFinalized(raw: Data([0x20, 0x04])) }),
            ("deliveryTransitions", { $0.deliveryTransitions.lastConfirmedObservation = later }),
            ("bolusState", { $0.bolusState = .noBolus }),
            ("insulinType", { $0.insulinType = .humalog }),
            ("bolusDose", { $0.bolusDose = nil }),
            ("bolusDose.deliveredUnits", { $0.bolusDose?.deliveredUnits = 2 }),
            ("pendingBolusFinalization", { $0.pendingBolusFinalization = nil }),
            ("pendingBolusFinalization.deliveredUnits", { $0.pendingBolusFinalization?.deliveredUnits = 0.5 }),
            ("basalDose", { $0.basalDose = UnfinalizedDose(basalRate: 0.8, insulinType: .novolog, startDate: t0) }),
            ("basalDose.estimatedEndDate", { $0.basalDose.estimatedEndDate = later }),
            ("basalRateSchedule", {
                $0.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 0.9)])!
            }),
            ("hasSyncedBasalRateSchedule", { $0.hasSyncedBasalRateSchedule = false }),
            ("autoAcknowledgeBasalAlerts", { $0.autoAcknowledgeBasalAlerts = false }),
            ("useSilentTones", { $0.useSilentTones = false }),
            ("currentPumpTime", { $0.currentPumpTime = nil }),
            ("lastPumpTimeCheckDate", { $0.lastPumpTimeCheckDate = nil }),
            ("lastSettingsCheckedAt", { $0.lastSettingsCheckedAt = nil }),
            ("quickBolusAnnun", { $0.quickBolusAnnun = nil }),
            ("reminderAnnun", { $0.reminderAnnun = nil }),
            ("alertAnnun", { $0.alertAnnun = nil }),
            ("alarmAnnun", { $0.alarmAnnun = nil }),
            ("generalAnnun", { $0.generalAnnun = nil }),
            ("pumpSoundsAwaitingWrite", { $0.pumpSoundsAwaitingWrite = false }),
            ("quickBolusEnabled", { $0.quickBolusEnabled = nil }),
            ("quickBolusEntryType", { $0.quickBolusEntryType = nil }),
            ("quickBolusIncrementUnits", { $0.quickBolusIncrementUnits = nil }),
            ("quickBolusIncrementCarbs", { $0.quickBolusIncrementCarbs = nil }),
            ("quickBolusStatus", { $0.quickBolusStatus = nil }),
            ("maxBasalLimitMilliunits", { $0.maxBasalLimitMilliunits = nil }),
            ("maxBasalLimitDefaultMilliunits", { $0.maxBasalLimitDefaultMilliunits = nil }),
            ("maxBolusLimitMilliunits", { $0.maxBolusLimitMilliunits = nil }),
            ("maxBolusLimitDefaultMilliunits", { $0.maxBolusLimitDefaultMilliunits = nil }),
            ("useControlIQ", { $0.useControlIQ = false }),
            ("pendingEnableClosedLoop", { $0.pendingEnableClosedLoop = false }),
            ("controlIQEnabled", { $0.controlIQEnabled = nil }),
            ("controlIQUserMode", { $0.controlIQUserMode = .exercise }),
            ("controlIQWeightLbs", { $0.controlIQWeightLbs = nil }),
            ("controlIQWeightUnit", { $0.controlIQWeightUnit = .pounds }),
            ("controlIQTotalDailyInsulin", { $0.controlIQTotalDailyInsulin = nil }),
            ("lastControlIQUpdate", { $0.lastControlIQUpdate = nil }),
            ("cgmSessionState", { $0.cgmSessionState = .stopped }),
            ("lastCGMStatusUpdate", { $0.lastCGMStatusUpdate = nil }),
            ("alertSnoozeEnabled", { $0.alertSnoozeEnabled = false }),
            ("alertSnoozeDuration", { $0.alertSnoozeDuration = .minutes(10) }),
            ("notificationCount", { $0.notificationCount = nil }),
            ("lastNotificationUpdate", { $0.lastNotificationUpdate = nil }),
            ("issuedAlertIdentifiers", { $0.issuedAlertIdentifiers.remove("alert-7") }),
            ("pumpClockSkewAlertIssued", { $0.pumpClockSkewAlertIssued = false }),
            ("forwardCGMAlerts", { $0.forwardCGMAlerts = false }),
            ("lastSiteChangeDate", { $0.lastSiteChangeDate = nil }),
            ("lastCartridgeChangeDate", { $0.lastCartridgeChangeDate = nil }),
            ("lastCannulaFillAmount", { $0.lastCannulaFillAmount = nil })
        ]
    }

    private static func populatedState() -> TandemPumpManagerState {
        let pumpSerial: UInt32 = 9_876_543
        let bolusDose = UnfinalizedDose(
            units: 2.4,
            duration: .seconds(120),
            activationType: .manualNoRecommendation,
            insulinType: .novolog,
            bolusId: 2004,
            now: t0
        )
        bolusDose.recordDeliveryStart(t0.addingTimeInterval(4), now: t0.addingTimeInterval(10))
        bolusDose.deliveredUnits = 1.1
        let pendingBolus = UnfinalizedDose(
            units: 1.5,
            duration: .seconds(75),
            activationType: .automatic,
            insulinType: .novolog,
            bolusId: 2003,
            now: t0.addingTimeInterval(-.minutes(30))
        )

        var state = TandemPumpManagerState(rawValue: [:])
        state.onboarded = true
        state.pumpState = PumpState(
            peripheralUuid: "6A9E3B1C-0000-4000-8000-000000000001",
            derivedSecret: Data([0x01, 0x02, 0x03, 0x04]),
            serverNonce: Data([0x05, 0x06, 0x07, 0x08]),
            timeSinceReset: 123_456,
            apiVersion: ApiVersion(major: 3, minor: 5),
            pumpSerial: pumpSerial,
            modelNumber: 21,
            softwareName: "t:slim X2",
            pumpModel: .TSLIM_X2
        )
        state.isConnected = true
        state.lastReconciliation = t0
        state.settings = TandemPumpManagerSettings(maxBolus: 9.5, maxTempBasalRate: 4.2, maxBasalScheduleEntry: 1.5)
        state.featureFlags = TandemFeatureFlags(overrides: [.controlIQSupport: true])
        state.latestInsulinOnBoard = 3.2
        state.lastReservoirReading = SimpleReservoirValue(startDate: t0, unitVolume: 142.5)
        state.lastReservoirReadingNeedsReport = true
        state.lastBatteryReading = .init(date: t0.addingTimeInterval(-120), chargeRemaining: 0.65, isCharging: true)
        state.lastBasalStatusDate = t0
        state.basalRateMismatchDetectedAt = t0
        state.basalProfileUpdateFailed = true
        state.historyBackfill = HistoryBackfillState(
            pumpSerial: pumpSerial,
            watermark: 4321,
            firstSeenFloor: t0.addingTimeInterval(-.hours(24))
        )
        state.bolusReportLedger = BolusReportLedger(
            trackingSince: t0.addingTimeInterval(-.hours(48)),
            entries: [
                .init(
                    bolusId: 2004,
                    pumpSerial: pumpSerial,
                    origin: .commanded,
                    raw: Data([0x20, 0x04]),
                    eventDate: t0,
                    automatic: false,
                    isFinalized: false
                )
            ]
        )
        state.bolusState = .inProgress(bolusDose.toDoseEntry(isMutable: true, now: t0))
        state.insulinType = .novolog
        state.bolusDose = bolusDose
        state.pendingBolusFinalization = pendingBolus
        state.basalDose = UnfinalizedDose(
            tempRate: 1.75,
            duration: .minutes(30),
            automatic: true,
            insulinType: .novolog,
            startDate: t0,
            tempRateId: 17
        )
        state.basalRateSchedule = BasalRateSchedule(
            dailyItems: [
                RepeatingScheduleValue(startTime: 0, value: 0.8),
                RepeatingScheduleValue(startTime: .hours(6), value: 1.1)
            ],
            timeZone: TimeZone(secondsFromGMT: 0)!
        )!
        state.hasSyncedBasalRateSchedule = true
        state.autoAcknowledgeBasalAlerts = true
        state.useSilentTones = true
        state.currentPumpTime = t0.addingTimeInterval(30)
        state.lastPumpTimeCheckDate = t0
        state.lastSettingsCheckedAt = t0
        state.quickBolusAnnun = .audioHigh
        state.reminderAnnun = .audioMedium
        state.alertAnnun = .audioLow
        state.alarmAnnun = .vibrate
        state.generalAnnun = .audioHigh
        state.pumpSoundsAwaitingWrite = true
        state.quickBolusEnabled = true
        state.quickBolusEntryType = 1
        state.quickBolusIncrementUnits = 500
        state.quickBolusIncrementCarbs = 2000
        state.quickBolusStatus = 1
        state.maxBasalLimitMilliunits = 4200
        state.maxBasalLimitDefaultMilliunits = 3000
        state.maxBolusLimitMilliunits = 9500
        state.maxBolusLimitDefaultMilliunits = 10000
        state.useControlIQ = true
        state.pendingEnableClosedLoop = true
        state.controlIQEnabled = true
        state.controlIQUserMode = .sleep
        state.controlIQWeightLbs = 154
        state.controlIQWeightUnit = .kilograms
        state.controlIQTotalDailyInsulin = 42
        state.lastControlIQUpdate = t0
        state.cgmSessionState = .active
        state.lastCGMStatusUpdate = t0
        state.alertSnoozeEnabled = true
        state.alertSnoozeDuration = .minutes(25)
        state.notificationCount = 3
        state.lastNotificationUpdate = t0
        state.issuedAlertIdentifiers = ["alarm-2", "alert-7"]
        state.pumpClockSkewAlertIssued = true
        state.forwardCGMAlerts = true
        state.lastSiteChangeDate = t0.addingTimeInterval(-.hours(50))
        state.lastCartridgeChangeDate = t0.addingTimeInterval(-.hours(26))
        state.lastCannulaFillAmount = 0.3
        return state
    }
}

extension Mirror {
    /// Property wrappers store `name` as `_name`, and `lazy` as `$__lazy_storage_$_name`.
    var storedPropertyNames: [String] {
        children.compactMap(\.label).map { label in
            for prefix in ["$__lazy_storage_$_", "_"] where label.hasPrefix(prefix) {
                return String(label.dropFirst(prefix.count))
            }
            return label
        }
    }
}
