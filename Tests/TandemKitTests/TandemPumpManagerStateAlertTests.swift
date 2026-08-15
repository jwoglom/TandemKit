import LoopKit
@testable import TandemKit
import XCTest

/// Persistence coverage for the LoopKit-alert fields on `TandemPumpManagerState`. Lives in
/// TandemKitTests (macOS-only) because `TandemPumpManagerState` is not part of the Linux
/// SwiftPM module; the reconciler's pure logic tests run on Linux in TandemCoreTests.
final class TandemPumpManagerStateAlertTests: XCTestCase {
    func testIssuedAlertIdentifiersRoundTripThroughRawValue() {
        let schedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 0.5)])!
        var state = TandemPumpManagerState(basalRateSchedule: schedule)
        state.issuedAlertIdentifiers = ["alarm.occlusion.2", "malfunction.12"]
        state.forwardCGMAlerts = true

        let restored = TandemPumpManagerState(rawValue: state.rawValue)

        XCTAssertEqual(restored.issuedAlertIdentifiers, ["alarm.occlusion.2", "malfunction.12"])
        XCTAssertTrue(restored.forwardCGMAlerts)
    }

    func testIssuedAlertIdentifiersDefaultEmptyOnLegacyRawValue() {
        // Raw state persisted by a driver version that predates alert surfacing.
        let restored = TandemPumpManagerState(rawValue: [:])

        XCTAssertTrue(restored.issuedAlertIdentifiers.isEmpty)
        XCTAssertFalse(restored.forwardCGMAlerts)
    }
}
