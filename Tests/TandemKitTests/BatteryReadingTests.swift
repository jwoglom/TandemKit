@testable import TandemKit
import XCTest

/// Coverage for the charging flag on persisted battery readings, split out from
/// TandemPumpManagerStateTests because these pin the charging field's own edge cases rather
/// than the broader state round trip.
///
/// The encode/decode helpers are fileprivate, so these go through the public
/// rawValue / init(rawValue:) round trip, which is the path LoopKit actually persists with.
final class BatteryReadingTests: XCTestCase {
    private let timestamp = Date(timeIntervalSinceReferenceDate: 987_654)

    private func makeState() -> TandemPumpManagerState {
        // init(rawValue:) is non-failable and defaults every field, so an empty dictionary
        // is the cheapest way to get a valid state to round-trip.
        TandemPumpManagerState(rawValue: [:])
    }

    func testBatteryReadingRoundTripsChargingState() throws {
        for isCharging in [true, false] {
            var state = makeState()
            state.lastBatteryReading = TandemPumpManagerState.BatteryReading(
                date: timestamp,
                chargeRemaining: 0.42,
                isCharging: isCharging
            )

            let restored = TandemPumpManagerState(rawValue: state.rawValue)
            let reading = try XCTUnwrap(restored.lastBatteryReading)

            XCTAssertEqual(reading, state.lastBatteryReading)
            XCTAssertEqual(reading.date, timestamp)
            XCTAssertEqual(reading.chargeRemaining, 0.42)
            XCTAssertEqual(reading.isCharging, isCharging)
        }
    }

    func testBatteryReadingDefaultsToNotCharging() {
        let reading = TandemPumpManagerState.BatteryReading(
            date: timestamp,
            chargeRemaining: 0.42
        )

        XCTAssertFalse(reading.isCharging)
    }

    func testStateSavedBeforeChargingWasTrackedDecodesAsNotCharging() throws {
        var state = makeState()
        state.lastBatteryReading = TandemPumpManagerState.BatteryReading(
            date: timestamp,
            chargeRemaining: 0.42,
            isCharging: true
        )

        // Drop the key to mimic state written by a build that predates charging tracking.
        var raw = state.rawValue
        var batteryRaw = try XCTUnwrap(raw["lastBatteryReading"] as? [String: Any])
        XCTAssertNotNil(batteryRaw.removeValue(forKey: "isCharging"))
        raw["lastBatteryReading"] = batteryRaw

        let restored = TandemPumpManagerState(rawValue: raw)
        let reading = try XCTUnwrap(restored.lastBatteryReading)

        XCTAssertEqual(reading.date, timestamp)
        XCTAssertEqual(reading.chargeRemaining, 0.42)
        XCTAssertFalse(reading.isCharging)
    }
}
