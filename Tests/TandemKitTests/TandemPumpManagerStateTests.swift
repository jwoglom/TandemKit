import XCTest
@testable import TandemKit
import LoopKit

final class TandemPumpManagerStateTests: XCTestCase {
    func testRawValueRoundTripPreservesLoopKitState() throws {
        let pumpState = PumpState(address: 0x12345678, derivedSecret: Data([0x01, 0x02]), serverNonce: Data([0x03, 0x04]))
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

        let state = TandemPumpManagerState(
            pumpState: pumpState,
            lastReconciliation: timestamp,
            lastReservoirReading: reservoirValue,
            basalDeliveryState: .tempBasal(basalDose),
            bolusState: .inProgress(bolusDose),
            deliveryIsUncertain: true
        )

        let rawValue = state.rawValue
        let restoredState = try XCTUnwrap(TandemPumpManagerState(rawValue: rawValue))

        XCTAssertEqual(state, restoredState)
        XCTAssertEqual(restoredState.lastReservoirReading?.startDate, reservoirValue.startDate)
        XCTAssertEqual(restoredState.lastReservoirReading?.unitVolume, reservoirValue.unitVolume)
        switch restoredState.basalDeliveryState {
        case .tempBasal(let dose)?:
            XCTAssertEqual(dose, basalDose)
        default:
            XCTFail("Expected temp basal dose to round-trip")
        }
        switch restoredState.bolusState {
        case .inProgress(let dose):
            XCTAssertEqual(dose, bolusDose)
        default:
            XCTFail("Expected bolus state to round-trip")
        }
        XCTAssertTrue(restoredState.deliveryIsUncertain)
    }

    func testVersion1RawValueMigration() throws {
        let pumpState = PumpState(address: 0x87654321)
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
    }
}
