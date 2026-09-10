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
            remoteId: 20, requestedNow: 1001, requestedLater: 0, correction: 1001,
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
            remoteId: 39, requestedNow: 210, requestedLater: 0, correction: 210,
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
            remoteId: 38, requestedNow: 920, requestedLater: 0, correction: 920,
            extendedDurationRequested: 0, deliveredTotal: 0
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "18019618981a71da020026040109012698030000980300000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    // Observed on a Tandem Mobi driven by Trio (Control-IQ off, no CGM paired), Sept 2026 BLE
    // capture. Byte 15 (`remoteId`, formerly `reserved`) equalled `bolusID & 0xFF` in 312/312
    // records of that capture; 2903 & 0xFF = 87 = 0x57 here. bolusTypeBitmask 5 = .now | .override
    // and bolusSource 8 = .bluetoothRemoteBolus for every Trio-initiated bolus. These records carry
    // header high nibble 1 (`1811`). See pumpX2 issue #78.
    func testBolusDeliveryHistoryLogRemoteIdStarted() {
        let expected = BolusDeliveryHistoryLog(
            pumpTimeSec: 589526845, sequenceNum: 640755, bolusID: 2903, bolusDeliveryStatus: 1,
            bolusTypeBitmask: 5, // .now, .override
            bolusSource: 8, // .bluetoothRemoteBolus
            remoteId: 87, requestedNow: 150, requestedLater: 0, correction: 0,
            extendedDurationRequested: 0, deliveredTotal: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "18113d772323f3c60900570b0105085796000000000000000000",
            expected
        )
        XCTAssertEqual(parsed.remoteId, 87)
        XCTAssertEqual(parsed.remoteId, parsed.bolusID & 0xFF)
        XCTAssertEqual(parsed.bolusSource, 8)
        XCTAssertEqual(parsed.bolusSourceEnum, .bluetoothRemoteBolus)
        XCTAssertEqual(parsed.bolusTypeBitmask, 5)
        XCTAssertEqual(parsed.bolusTypes, [.now, .override])
        XCTAssertEqual(parsed.bolusDeliveryStatus, 1)
        XCTAssertEqual(parsed.requestedNow, 150)
        XCTAssertEqual(parsed.deliveredTotal, 0)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testBolusDeliveryHistoryLogRemoteIdCompleted() {
        let expected = BolusDeliveryHistoryLog(
            pumpTimeSec: 589526849, sequenceNum: 640760, bolusID: 2903, bolusDeliveryStatus: 0,
            bolusTypeBitmask: 5, // .now, .override
            bolusSource: 8, // .bluetoothRemoteBolus
            remoteId: 87, requestedNow: 150, requestedLater: 0, correction: 0,
            extendedDurationRequested: 0, deliveredTotal: 150
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "181141772323f8c60900570b0005085796000000000000009600",
            expected
        )
        XCTAssertEqual(parsed.remoteId, 87)
        XCTAssertEqual(parsed.remoteId, parsed.bolusID & 0xFF)
        XCTAssertEqual(parsed.bolusSource, 8)
        XCTAssertEqual(parsed.bolusSourceEnum, .bluetoothRemoteBolus)
        XCTAssertEqual(parsed.bolusTypeBitmask, 5)
        XCTAssertEqual(parsed.bolusTypes, [.now, .override])
        XCTAssertEqual(parsed.bolusDeliveryStatus, 0)
        XCTAssertEqual(parsed.requestedNow, 150)
        XCTAssertEqual(parsed.deliveredTotal, 150)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
