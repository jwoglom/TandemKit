import LoopKit
@testable import TandemCore
@testable import TandemKit
import XCTest

final class TandemPumpManagerStateTests: XCTestCase {
    func testRawValueRoundTripPreservesLoopKitState() throws {
        let pumpState = PumpState(address: 0x1234_5678, derivedSecret: Data([0x01, 0x02]), serverNonce: Data([0x03, 0x04]))
        let timestamp = Date(timeIntervalSinceReferenceDate: 1_234_567)
        let reservoirValue = SimpleReservoirValue(startDate: timestamp, unitVolume: 142.5)
        let basalDose = DoseEntry(
            type: .tempBasal,
            startDate: timestamp,
            endDate: timestamp.addingTimeInterval(1800),
            value: 1.2,
            unit: .unitsPerHour
        )
        let bolusDose = DoseEntry(
            type: .bolus,
            startDate: timestamp,
            endDate: timestamp.addingTimeInterval(120),
            value: 2.4,
            unit: .units
        )

        let battery = TandemPumpManagerState.BatteryReading(date: timestamp, chargeRemaining: 0.65)
        let schedule = BasalRateSchedule(
            items: [
                RepeatingScheduleValue(startTime: 0, value: 0.8),
                RepeatingScheduleValue(startTime: 3600, value: 1.1)
            ],
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        let state = TandemPumpManagerState(
            pumpState: pumpState,
            lastReconciliation: timestamp,
            lastReservoirReading: reservoirValue,
            lastBatteryReading: battery,
            basalDeliveryState: .tempBasal(basalDose),
            lastBasalStatusDate: timestamp,
            bolusState: .inProgress(bolusDose),
            deliveryIsUncertain: true,
            basalRateSchedule: schedule,
            insulinDeliveryActionsEnabled: true,
            connectionSharingEnabled: true
        )

        let rawValue = state.rawValue
        let restoredState = try XCTUnwrap(TandemPumpManagerState(rawValue: rawValue))

        XCTAssertEqual(state, restoredState)
        XCTAssertEqual(restoredState.lastReservoirReading?.startDate, reservoirValue.startDate)
        XCTAssertEqual(restoredState.lastReservoirReading?.unitVolume, reservoirValue.unitVolume)
        XCTAssertEqual(restoredState.lastBatteryReading?.date, battery.date)
        XCTAssertEqual(restoredState.lastBatteryReading?.chargeRemaining, battery.chargeRemaining)
        XCTAssertEqual(restoredState.lastBasalStatusDate, timestamp)
        switch restoredState.basalDeliveryState {
        case let .tempBasal(dose)?:
            XCTAssertEqual(dose, basalDose)
        default:
            XCTFail("Expected temp basal dose to round-trip")
        }
        switch restoredState.bolusState {
        case let .inProgress(dose):
            XCTAssertEqual(dose, bolusDose)
        default:
            XCTFail("Expected bolus state to round-trip")
        }
        XCTAssertTrue(restoredState.deliveryIsUncertain)
        XCTAssertEqual(restoredState.basalRateSchedule, schedule)
        XCTAssertTrue(restoredState.insulinDeliveryActionsEnabled)
        XCTAssertTrue(restoredState.connectionSharingEnabled)
    }

    func testVersion1RawValueMigration() throws {
        let pumpState = PumpState(address: 0x8765_4321)
        let lastReconciliation = Date(timeIntervalSinceReferenceDate: 2_468_000)
        let legacyRaw: [String: Any] = [
            "version": 1,
            "pumpState": pumpState.rawValue,
            "lastReconciliation": lastReconciliation.timeIntervalSinceReferenceDate
        ]

        let restoredState = try XCTUnwrap(TandemPumpManagerState(rawValue: legacyRaw))

        XCTAssertEqual(restoredState.pumpState, pumpState)
        XCTAssertEqual(restoredState.lastReconciliation, lastReconciliation)
        XCTAssertNil(restoredState.lastReservoirReading)
        XCTAssertNil(restoredState.basalDeliveryState)
        XCTAssertEqual(restoredState.bolusState, .noBolus)
        XCTAssertFalse(restoredState.deliveryIsUncertain)
        XCTAssertFalse(restoredState.insulinDeliveryActionsEnabled)
        XCTAssertFalse(restoredState.connectionSharingEnabled)
    }

    func testManagerRestoresCachedStatusFromRawState() throws {
        let timestamp = Date(timeIntervalSinceReferenceDate: 3_456_789)
        let pumpState = PumpState(
            address: 0xABCD_EF12,
            derivedSecret: Data([0x10, 0x11, 0x12, 0x13]),
            serverNonce: Data([0x20, 0x21, 0x22, 0x23])
        )
        let reservoir = SimpleReservoirValue(startDate: timestamp, unitVolume: 142.0)
        let battery = TandemPumpManagerState.BatteryReading(date: timestamp.addingTimeInterval(-120), chargeRemaining: 0.55)
        let basalState: PumpManagerStatus.BasalDeliveryState = .suspended(timestamp)
        let schedule = BasalRateSchedule(
            items: [RepeatingScheduleValue(startTime: 0, value: 0.75)],
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        let settings = TandemPumpManagerSettings(
            maxBolus: 9.5,
            maxTempBasalRate: 4.2,
            maxBasalScheduleEntry: 1.5,
            maxInsulinOnBoard: nil
        )

        let state = TandemPumpManagerState(
            pumpState: pumpState,
            lastReconciliation: timestamp,
            settings: settings,
            lastReservoirReading: reservoir,
            lastBatteryReading: battery,
            basalDeliveryState: basalState,
            lastBasalStatusDate: timestamp,
            bolusState: .noBolus,
            deliveryIsUncertain: true,
            basalRateSchedule: schedule
        )

        PumpStateSupplier.storePairingArtifacts(derivedSecret: nil, serverNonce: nil)
        defer { PumpStateSupplier.storePairingArtifacts(derivedSecret: nil, serverNonce: nil) }

        let manager = try XCTUnwrap(TandemPumpManager(rawState: state.rawValue))

        XCTAssertEqual(manager.pumpBatteryChargeRemaining, battery.chargeRemaining)
        XCTAssertEqual(manager.status.pumpBatteryChargeRemaining, battery.chargeRemaining)
        XCTAssertEqual(manager.status.basalDeliveryState, basalState)
        XCTAssertTrue(manager.status.deliveryIsUncertain)
        XCTAssertEqual(manager.reservoirLevel?.startDate, reservoir.startDate)
        XCTAssertEqual(manager.reservoirLevel?.unitVolume, reservoir.unitVolume)

        let restoredState = try XCTUnwrap(TandemPumpManagerState(rawValue: manager.rawState))
        XCTAssertEqual(restoredState.settings.maxBolus, settings.maxBolus)
        XCTAssertEqual(restoredState.settings.maxTempBasalRate, settings.maxTempBasalRate)
        XCTAssertEqual(restoredState.basalRateSchedule, schedule)
        XCTAssertEqual(restoredState.lastBatteryReading?.chargeRemaining, battery.chargeRemaining)
        XCTAssertEqual(restoredState.lastReservoirReading?.unitVolume, reservoir.unitVolume)

        let derivedSecret = PumpStateSupplier.getDerivedSecret()
        XCTAssertEqual(derivedSecret, pumpState.derivedSecret)
        XCTAssertFalse(restoredState.insulinDeliveryActionsEnabled)
        XCTAssertFalse(restoredState.connectionSharingEnabled)
    }
}
