import LoopKit
@testable import TandemKit
import XCTest

/// `rawState` is the only thing that survives an app restart: everything the driver knows about the
/// paired pump — including the derived secret it needs to reconnect without re-pairing — has to
/// make the round trip through `[String: Any]` and back. These tests pin that contract.
final class TandemPumpManagerStateTests: XCTestCase {
    private let timestamp = Date(timeIntervalSinceReferenceDate: 1_234_567)

    private func makePopulatedState() -> TandemPumpManagerState {
        var state = TandemPumpManagerState(rawValue: [:])

        state.onboarded = true
        state.pumpState = PumpState(
            peripheralUuid: "6A9E3B1C-0000-4000-8000-000000000001",
            derivedSecret: Data([0x01, 0x02, 0x03, 0x04]),
            serverNonce: Data([0x05, 0x06, 0x07, 0x08]),
            timeSinceReset: 123_456,
            pumpSerial: 9_876_543,
            modelNumber: 21,
            softwareName: "t:slim X2"
        )
        state.lastReconciliation = timestamp
        state.settings = TandemPumpManagerSettings(
            maxBolus: 9.5,
            maxTempBasalRate: 4.2,
            maxBasalScheduleEntry: 1.5
        )
        state.lastReservoirReading = SimpleReservoirValue(startDate: timestamp, unitVolume: 142.5)
        state.lastBatteryReading = TandemPumpManagerState.BatteryReading(
            date: timestamp.addingTimeInterval(-120),
            chargeRemaining: 0.65,
            isCharging: true
        )
        state.lastBasalStatusDate = timestamp
        state.insulinType = .novolog
        state.basalRateSchedule = BasalRateSchedule(
            dailyItems: [
                RepeatingScheduleValue(startTime: 0, value: 0.8),
                RepeatingScheduleValue(startTime: 3600, value: 1.1)
            ],
            timeZone: TimeZone(secondsFromGMT: 0)!
        )!
        state.hasSyncedBasalRateSchedule = true
        state.useControlIQ = true
        state.controlIQEnabled = true
        state.controlIQWeightLbs = 154
        state.controlIQWeightUnit = .kilograms
        state.controlIQTotalDailyInsulin = 42
        state.lastControlIQUpdate = timestamp
        state.autoAcknowledgeBasalAlerts = true
        state.useSilentTones = true
        state.alertSnoozeEnabled = true
        state.alertSnoozeDuration = .minutes(25)
        state.notificationCount = 3
        state.currentPumpTime = timestamp
        state.lastPumpTimeCheckDate = timestamp
        state.maxBasalLimitMilliunits = 4200
        state.maxBolusLimitMilliunits = 9500

        return state
    }

    func testRawValueRoundTripPreservesPairingArtifacts() throws {
        let state = makePopulatedState()
        let restored = TandemPumpManagerState(rawValue: state.rawValue)

        // Without these the driver cannot reconnect after a restart and the user has to re-pair.
        XCTAssertEqual(restored.pumpState.derivedSecret, state.pumpState.derivedSecret)
        XCTAssertEqual(restored.pumpState.serverNonce, state.pumpState.serverNonce)
        XCTAssertEqual(restored.pumpState.peripheralUuid, state.pumpState.peripheralUuid)
        XCTAssertEqual(restored.pumpState, state.pumpState)
        XCTAssertTrue(restored.onboarded)
    }

    func testRawValueRoundTripPreservesTherapyState() throws {
        let state = makePopulatedState()
        let restored = TandemPumpManagerState(rawValue: state.rawValue)

        XCTAssertEqual(restored.lastReconciliation, timestamp)
        XCTAssertEqual(restored.lastBasalStatusDate, timestamp)
        XCTAssertEqual(restored.settings.maxBolus, 9.5)
        XCTAssertEqual(restored.settings.maxTempBasalRate, 4.2)
        XCTAssertEqual(restored.settings.maxBasalScheduleEntry, 1.5)
        XCTAssertEqual(restored.lastReservoirReading?.startDate, timestamp)
        XCTAssertEqual(restored.lastReservoirReading?.unitVolume, 142.5)
        XCTAssertEqual(restored.lastBatteryReading?.date, timestamp.addingTimeInterval(-120))
        XCTAssertEqual(restored.lastBatteryReading?.chargeRemaining, 0.65)
        XCTAssertEqual(restored.lastBatteryReading?.isCharging, true)
        XCTAssertEqual(restored.insulinType, .novolog)
        XCTAssertEqual(restored.basalRateSchedule, state.basalRateSchedule)
        XCTAssertTrue(restored.hasSyncedBasalRateSchedule)
    }

    func testRawValueRoundTripPreservesPumpSettings() throws {
        let state = makePopulatedState()
        let restored = TandemPumpManagerState(rawValue: state.rawValue)

        XCTAssertTrue(restored.useControlIQ)
        XCTAssertEqual(restored.controlIQEnabled, true)
        XCTAssertEqual(restored.controlIQWeightLbs, 154)
        XCTAssertEqual(restored.controlIQWeightUnit, .kilograms)
        XCTAssertEqual(restored.controlIQTotalDailyInsulin, 42)
        XCTAssertEqual(restored.lastControlIQUpdate, timestamp)
        XCTAssertTrue(restored.autoAcknowledgeBasalAlerts)
        XCTAssertTrue(restored.useSilentTones)
        XCTAssertTrue(restored.alertSnoozeEnabled)
        XCTAssertEqual(restored.alertSnoozeDuration, .minutes(25))
        XCTAssertEqual(restored.notificationCount, 3)
        XCTAssertEqual(restored.currentPumpTime, timestamp)
        XCTAssertEqual(restored.lastPumpTimeCheckDate, timestamp)
        XCTAssertEqual(restored.maxBasalLimitMilliunits, 4200)
        XCTAssertEqual(restored.maxBolusLimitMilliunits, 9500)
    }

    func testInProgressBolusRoundTrips() throws {
        var state = makePopulatedState()
        let bolusDose = UnfinalizedDose(
            units: 2.4,
            duration: .seconds(120),
            activationType: .manualNoRecommendation,
            insulinType: .novolog,
            bolusId: 2004
        )
        bolusDose.deliveredUnits = 1.1
        state.bolusDose = bolusDose
        state.bolusState = .inProgress(bolusDose.toDoseEntry(isMutable: true))

        let restored = TandemPumpManagerState(rawValue: state.rawValue)

        let restoredDose = try XCTUnwrap(restored.bolusDose)
        XCTAssertEqual(restoredDose.bolusId, 2004)
        XCTAssertEqual(restoredDose.value, 2.4)
        XCTAssertEqual(restoredDose.deliveredUnits, 1.1)
        XCTAssertEqual(restoredDose.startDate, bolusDose.startDate)
        XCTAssertEqual(restoredDose.estimatedEndDate, bolusDose.estimatedEndDate)
        XCTAssertEqual(restoredDose.insulinType, .novolog)
        XCTAssertFalse(restoredDose.automatic)

        guard case let .inProgress(dose) = restored.bolusState else {
            return XCTFail("Expected an in-progress bolus to round-trip, got \(restored.bolusState)")
        }
        XCTAssertEqual(dose.programmedUnits, 2.4)
    }

    func testTempBasalRoundTripsThroughBasalDose() throws {
        var state = makePopulatedState()
        let tempBasal = UnfinalizedDose(
            tempRate: 1.75,
            duration: .minutes(30),
            automatic: true,
            insulinType: .novolog
        )
        state.basalDose = tempBasal

        let restored = TandemPumpManagerState(rawValue: state.rawValue)

        XCTAssertEqual(restored.basalDose.type, .tempBasal)
        XCTAssertEqual(restored.basalDose.value, 1.75)
        XCTAssertTrue(restored.basalDose.automatic)
        XCTAssertEqual(restored.basalDose.startDate, tempBasal.startDate)
        XCTAssertEqual(restored.basalDose.estimatedEndDate, tempBasal.estimatedEndDate)

        guard case let .tempBasal(dose) = restored.basalDeliveryState else {
            return XCTFail("Expected temp basal delivery state, got \(restored.basalDeliveryState)")
        }
        XCTAssertEqual(dose.unitsPerHour, 1.75)
    }

    /// An empty dictionary is what a fresh install hands back before the pump is ever paired, so it
    /// has to decode into a usable state rather than trapping on a missing key.
    func testEmptyRawValueDecodesToSafeDefaults() {
        let state = TandemPumpManagerState(rawValue: [:])

        XCTAssertFalse(state.onboarded)
        XCTAssertFalse(state.isConnected)
        XCTAssertNil(state.pumpState.derivedSecret)
        XCTAssertNil(state.pumpState.serverNonce)
        XCTAssertNil(state.lastReconciliation)
        XCTAssertNil(state.lastReservoirReading)
        XCTAssertNil(state.lastBatteryReading)
        XCTAssertNil(state.bolusDose)
        XCTAssertEqual(state.bolusState, .noBolus)
        XCTAssertNil(state.settings.maxBolus)
        XCTAssertFalse(state.useControlIQ)
        XCTAssertFalse(state.hasSyncedBasalRateSchedule)
    }

    /// Builds before the weight unit was tracked stored `controlIQWeight` in whichever unit the pump
    /// displayed, so that value cannot be read back as the pounds the pump is sent. It is dropped
    /// instead of guessed, and the next sync repopulates it.
    func testLegacyControlIQWeightKeyIsNotRestored() {
        var raw = TandemPumpManagerState(rawValue: [:]).rawValue
        raw["controlIQWeight"] = 70
        raw.removeValue(forKey: "controlIQWeightLbs")

        let restored = TandemPumpManagerState(rawValue: raw)

        XCTAssertNil(restored.controlIQWeightLbs)
        XCTAssertNil(restored.controlIQWeightUnit)
    }

    /// `isConnected` is deliberately not restored: a stale `true` would make the driver believe it
    /// still had a live BLE link on launch.
    func testIsConnectedIsNotRestored() {
        var state = TandemPumpManagerState(rawValue: [:])
        state.isConnected = true

        XCTAssertFalse(TandemPumpManagerState(rawValue: state.rawValue).isConnected)
    }

    func testManagerRestoresCachedStatusFromRawState() throws {
        let state = makePopulatedState()
        let manager = try XCTUnwrap(TandemPumpManager(rawState: state.rawValue))

        XCTAssertEqual(manager.status.pumpBatteryChargeRemaining, 0.65)
        XCTAssertEqual(manager.reservoirLevel?.unitVolume, 142.5)
        XCTAssertTrue(manager.isOnboarded)

        let restored = TandemPumpManagerState(rawValue: manager.rawState)
        XCTAssertEqual(restored.settings.maxBolus, 9.5)
        XCTAssertEqual(restored.pumpState.derivedSecret, state.pumpState.derivedSecret)
    }

    /// Auto-acknowledgement of basal alerts is mandatory: oref routinely sets a zero basal rate and
    /// the pump alerts on every one, so a fresh install starts with it on and cannot turn it off.
    func testAutoAcknowledgeBasalAlertsDefaultsOn() {
        XCTAssertTrue(TandemPumpManagerState(rawValue: [:]).autoAcknowledgeBasalAlerts)
    }

    /// State persisted while the setting was still user-facing may hold `false`. Those pumps have to
    /// migrate on rather than stay silently off, so the stored value is ignored on decode.
    func testAutoAcknowledgeBasalAlertsMigratesOnFromPersistedState() {
        var raw = makePopulatedState().rawValue
        raw["autoAcknowledgeBasalAlerts"] = false

        XCTAssertTrue(TandemPumpManagerState(rawValue: raw).autoAcknowledgeBasalAlerts)
    }
}
