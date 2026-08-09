@testable import TandemKit
import XCTest

/// Coverage for the charging flag on persisted battery readings.
///
/// These live outside TandemPumpManagerStateTests because that file is excluded from the
/// TandemKitTests target (see scripts/check_xcodeproj_source_membership.rb), so anything
/// added there would never run.
final class BatteryReadingTests: XCTestCase {
    func testBatteryReadingRoundTripsChargingState() throws {
        let timestamp = Date(timeIntervalSinceReferenceDate: 987_654)

        for isCharging in [true, false] {
            let reading = TandemPumpManagerState.BatteryReading(
                date: timestamp,
                chargeRemaining: 0.42,
                isCharging: isCharging
            )
            let raw = TandemPumpManagerState.encodeBatteryReading(reading)
            let decoded = try XCTUnwrap(TandemPumpManagerState.decodeBatteryReading(from: raw))

            XCTAssertEqual(decoded, reading)
            XCTAssertEqual(decoded.isCharging, isCharging)
        }
    }

    func testBatteryReadingDefaultsToNotCharging() {
        let reading = TandemPumpManagerState.BatteryReading(
            date: Date(timeIntervalSinceReferenceDate: 987_654),
            chargeRemaining: 0.42
        )

        XCTAssertFalse(reading.isCharging)
    }

    func testBatteryReadingSavedBeforeChargingWasTrackedDecodesAsNotCharging() throws {
        let timestamp = Date(timeIntervalSinceReferenceDate: 987_654)
        let legacyRaw: [String: Any] = [
            "date": timestamp.timeIntervalSinceReferenceDate,
            "chargeRemaining": 0.42
        ]

        let decoded = try XCTUnwrap(TandemPumpManagerState.decodeBatteryReading(from: legacyRaw))

        XCTAssertEqual(decoded.date, timestamp)
        XCTAssertEqual(decoded.chargeRemaining, 0.42)
        XCTAssertFalse(decoded.isCharging)
    }
}
