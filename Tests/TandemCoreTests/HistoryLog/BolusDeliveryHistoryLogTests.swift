@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `BolusDeliveryHistoryLogTest` (from pumpX2 PR #120, the branch with the
/// corrected bitmask `BolusType` enum: NOW=1, LATER=2, OVERRIDE=4, CORRECTION=8, CARB=16,
/// EATING_SOON_MODE=32).
///
/// The Swift convenience init takes `bolusTypeBitmask`/`bolusSource` as raw `Int`s rather than the
/// Java constructor's `Set<BolusType>`/`BolusSource` enum, so each Java `Set.of(...)` is
/// translated into its equivalent bitmask (`NOW|CORRECTION` = 1|8 = 9) and each `BolusSource` enum
/// case into its raw id.
final class BolusDeliveryHistoryLogTests: XCTestCase {
    func testBolusDeliveryHistoryLog1() {
        let expected = BolusDeliveryHistoryLog(
            pumpTimeSec: 446066139, sequenceNum: 183687, bolusID: 1044, bolusDeliveryStatus: 0,
            bolusTypeBitmask: 9, // .now, .correction
            bolusSource: 7, // .controlIQAutoBolus
            reserved: 20, requestedNow: 1001, requestedLater: 0, correction: 1001,
            extendedDurationRequested: 0, deliveredTotal: 1001
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "1801db6d961a87cd0200140400090714e9030000e9030000e903",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testBolusDeliveryHistoryLog2() {
        let expected = BolusDeliveryHistoryLog(
            pumpTimeSec: 446175714, sequenceNum: 187031, bolusID: 1063, bolusDeliveryStatus: 0,
            bolusTypeBitmask: 9, // .now, .correction
            bolusSource: 1, // .gui
            reserved: 39, requestedNow: 210, requestedLater: 0, correction: 210,
            extendedDurationRequested: 0, deliveredTotal: 210
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "1801e219981a97da0200270400090127d2000000d2000000d200",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testBolusDeliveryHistoryLog3() {
        let expected = BolusDeliveryHistoryLog(
            pumpTimeSec: 446175382, sequenceNum: 186993, bolusID: 1062, bolusDeliveryStatus: 1,
            bolusTypeBitmask: 9, // .now, .correction
            bolusSource: 1, // .gui
            reserved: 38, requestedNow: 920, requestedLater: 0, correction: 920,
            extendedDurationRequested: 0, deliveredTotal: 0
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "18019618981a71da020026040109012698030000980300000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
