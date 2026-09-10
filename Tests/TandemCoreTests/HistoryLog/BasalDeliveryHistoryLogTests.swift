@testable import TandemKit
import XCTest

/// Ported from pumpX2's `BasalDeliveryHistoryLogTest`.
final class BasalDeliveryHistoryLogTests: XCTestCase {
    // Bytes 12-13 are `basalDeliveryFlags` (pumpX2 issue #77): 0 for steady-state delivery, 3 when
    // the basal command changed in the interval or while suspended. The three pumpX2 fixtures below
    // all carry 0, so they rely on the defaulted `basalDeliveryFlags: 0` initializer argument; the
    // Mobi captures further down exercise the nonzero value.
    func testBasalDeliveryHistoryLog1() {
        let expected = BasalDeliveryHistoryLog(
            pumpTimeSec: 580771325,
            sequenceNum: 490788,
            commandedRateSource: 3,
            commandedRate: 1000,
            profileBasalRate: 1000,
            algorithmRate: 1000,
            tempRate: 65535
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "1711fddd9d22247d070003000000e803e803e803ffff00000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testBasalDeliveryHistoryLog2() {
        let expected = BasalDeliveryHistoryLog(
            pumpTimeSec: 580640885,
            sequenceNum: 485442,
            commandedRateSource: 1,
            commandedRate: 1200,
            profileBasalRate: 1200,
            algorithmRate: 65535,
            tempRate: 65535
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "171175e09b224268070001000000b004b004ffffffff00000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testBasalDeliveryHistoryLog3() {
        // suspend record: no commanded rate, algorithm/temp rate both "n/a" (0xffff)
        let expected = BasalDeliveryHistoryLog(
            pumpTimeSec: 580601530,
            sequenceNum: 483924,
            commandedRateSource: 0,
            commandedRate: 0,
            profileBasalRate: 1000,
            algorithmRate: 65535,
            tempRate: 65535
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "1711ba469b2254620700000000000000e803ffffffff00000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    // Observed on a Tandem Mobi driven by Trio (Control-IQ off, no CGM paired), Sept 2026 BLE capture.
    // Temp rate 160% activated in the preceding 5-minute interval: commandedRate == tempRate,
    // basalDeliveryFlags == 3 because the commanded rate changed vs the previous record.
    func testBasalDeliveryHistoryLogMobiTempRateChanged() {
        let expected = BasalDeliveryHistoryLog(
            pumpTimeSec: 589526924,
            sequenceNum: 640766,
            commandedRateSource: 2,
            basalDeliveryFlags: 3,
            commandedRate: 1600,
            profileBasalRate: 1000,
            algorithmRate: 65535,
            tempRate: 1600
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "17118c772323fec60900020003004006e803ffff400600000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.commandedRateSource, 2)
        XCTAssertEqual(parsed.commandedRateSourceEnum, .tempRate)
        XCTAssertEqual(parsed.basalDeliveryFlags, 3)
        XCTAssertEqual(parsed.commandedRate, 1600)
        XCTAssertEqual(parsed.profileBasalRate, 1000)
        XCTAssertEqual(parsed.algorithmRate, 65535)
        XCTAssertEqual(parsed.tempRate, 1600)
    }

    // Observed on a Tandem Mobi driven by Trio (Control-IQ off, no CGM paired), Sept 2026 BLE capture.
    // Steady state: a 0% temp rate active and unchanged since the previous record, so
    // basalDeliveryFlags == 0 even though commandedRateSource still reports the temp rate.
    func testBasalDeliveryHistoryLogMobiSteadyStateTempRate() {
        let expected = BasalDeliveryHistoryLog(
            pumpTimeSec: 589527525,
            sequenceNum: 640786,
            commandedRateSource: 2,
            basalDeliveryFlags: 0,
            commandedRate: 0,
            profileBasalRate: 1000,
            algorithmRate: 65535,
            tempRate: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "1711e579232312c70900020000000000e803ffff000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.commandedRateSourceEnum, .tempRate)
        XCTAssertEqual(parsed.basalDeliveryFlags, 0)
        XCTAssertEqual(parsed.commandedRate, 0)
        XCTAssertEqual(parsed.tempRate, 0)
    }

    // Observed on a Tandem Mobi driven by Trio (Control-IQ off, no CGM paired), Sept 2026 BLE capture.
    // First record after the 08:00 profile segment change (1000 -> 1200 mU/hr): no temp rate
    // event in the interval, but profileBasalRate changed, so basalDeliveryFlags == 3.
    func testBasalDeliveryHistoryLogMobiProfileSegmentChanged() {
        let expected = BasalDeliveryHistoryLog(
            pumpTimeSec: 589536234,
            sequenceNum: 641124,
            commandedRateSource: 2,
            basalDeliveryFlags: 3,
            commandedRate: 1080,
            profileBasalRate: 1200,
            algorithmRate: 65535,
            tempRate: 1080
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "1711ea9b232364c80900020003003804b004ffff380400000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.commandedRateSourceEnum, .tempRate)
        XCTAssertEqual(parsed.basalDeliveryFlags, 3)
        XCTAssertEqual(parsed.profileBasalRate, 1200)
    }

    // Observed on a Tandem Mobi driven by Trio (Control-IQ off, no CGM paired), Sept 2026 BLE capture.
    // Suspended: commandedRateSource == 0, commandedRate == 0, algorithm/temp rate both "n/a"
    // (0xffff), and basalDeliveryFlags == 3 as in nearly every record written while suspended.
    func testBasalDeliveryHistoryLogMobiSuspended() {
        let expected = BasalDeliveryHistoryLog(
            pumpTimeSec: 589553351,
            sequenceNum: 641943,
            commandedRateSource: 0,
            basalDeliveryFlags: 3,
            commandedRate: 0,
            profileBasalRate: 1000,
            algorithmRate: 65535,
            tempRate: 65535
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "1711c7de232397cb0900000003000000e803ffffffff00000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.commandedRateSource, 0)
        XCTAssertEqual(parsed.commandedRateSourceEnum, .suspended)
        XCTAssertEqual(parsed.basalDeliveryFlags, 3)
        XCTAssertEqual(parsed.tempRate, 65535)
    }

    func testCommandedRateSourceEnumMapsKnownValuesOnly() {
        XCTAssertEqual(BasalDeliveryHistoryLog.CommandedRateSource(rawValue: 0), .suspended)
        XCTAssertEqual(BasalDeliveryHistoryLog.CommandedRateSource(rawValue: 1), .profile)
        XCTAssertEqual(BasalDeliveryHistoryLog.CommandedRateSource(rawValue: 2), .tempRate)
        XCTAssertEqual(BasalDeliveryHistoryLog.CommandedRateSource(rawValue: 3), .algorithm)
        XCTAssertEqual(BasalDeliveryHistoryLog.CommandedRateSource(rawValue: 4), .tempRateAndAlgorithm)
        XCTAssertNil(BasalDeliveryHistoryLog.CommandedRateSource(rawValue: 5))
    }
}
