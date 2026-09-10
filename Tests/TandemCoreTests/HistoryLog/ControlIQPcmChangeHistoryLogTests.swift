@testable import TandemKit
import XCTest

/// Ported from pumpX2's `ControlIQPcmChangeHistoryLogTest`.
final class ControlIQPcmChangeHistoryLogTests: XCTestCase {
    func testControlIQPcmChangeHistoryLog1() {
        let expected = ControlIQPcmChangeHistoryLog(
            pumpTimeSec: 580773244,
            sequenceNum: 490889,
            currentPcm: 0,
            previousPcm: 3,
            pumpSuspended: 1,
            calculationAvailable: 1,
            cgmAvailable: 1,
            closedLoopPreferred: 1,
            sufficientClosedLoopParams: 1
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "e6107ce59d22897d070000030101010101000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testControlIQPcmChangeHistoryLog2() {
        let expected = ControlIQPcmChangeHistoryLog(
            pumpTimeSec: 580720759,
            sequenceNum: 488634,
            currentPcm: 3,
            previousPcm: 2,
            pumpSuspended: 0,
            calculationAvailable: 1,
            cgmAvailable: 1,
            closedLoopPreferred: 1,
            sufficientClosedLoopParams: 1
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "e61077189d22ba74070003020001010101000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    // Observed on a Tandem Mobi driven by Trio (Control-IQ off, no CGM paired), Sept 2026 BLE capture.
    // Eight records, one pair per suspend/resume. With Control-IQ off the PCM only toggles between
    // NO_CONTROL (0, while suspended) and OPEN_LOOP (1, while delivering); cgmAvailable and
    // closedLoopPreferred stay 0 throughout and every boolean field is strictly 0/1.
    func testControlIQPcmChangeHistoryLogMobiSuspend() {
        let expected = ControlIQPcmChangeHistoryLog(
            pumpTimeSec: 589553316,
            sequenceNum: 641937,
            currentPcm: 0,
            previousPcm: 1,
            pumpSuspended: 1,
            calculationAvailable: 1,
            cgmAvailable: 0,
            closedLoopPreferred: 0,
            sufficientClosedLoopParams: 1
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "e610a4de232391cb090000010101000001000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)

        XCTAssertEqual(parsed.currentPcmEnum, .noControl)
        XCTAssertEqual(parsed.previousPcmEnum, .openLoop)
        XCTAssertTrue(parsed.isPumpSuspended)
        XCTAssertTrue(parsed.isCalculationAvailable)
        XCTAssertFalse(parsed.isCgmAvailable)
        XCTAssertFalse(parsed.isClosedLoopPreferred)
        XCTAssertTrue(parsed.isSufficientClosedLoopParams)
    }

    func testControlIQPcmChangeHistoryLogMobiResume() {
        let expected = ControlIQPcmChangeHistoryLog(
            pumpTimeSec: 589555699,
            sequenceNum: 642015,
            currentPcm: 1,
            previousPcm: 0,
            pumpSuspended: 0,
            calculationAvailable: 1,
            cgmAvailable: 0,
            closedLoopPreferred: 0,
            sufficientClosedLoopParams: 1
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "e610f3e72323dfcb090001000001000001000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)

        XCTAssertEqual(parsed.currentPcmEnum, .openLoop)
        XCTAssertEqual(parsed.previousPcmEnum, .noControl)
        XCTAssertFalse(parsed.isPumpSuspended)
        XCTAssertTrue(parsed.isCalculationAvailable)
        XCTAssertFalse(parsed.isCgmAvailable)
        XCTAssertFalse(parsed.isClosedLoopPreferred)
        XCTAssertTrue(parsed.isSufficientClosedLoopParams)
    }
}
