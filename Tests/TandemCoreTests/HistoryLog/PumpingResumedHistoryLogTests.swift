@testable import TandemKit
import XCTest

/// Ported from pumpX2's `PumpingResumedHistoryLogTest`.
///
/// See `PumpingSuspendedHistoryLogTests` for the adaptation notes on the dropped
/// `testSingleIgnoringBaseFields` helper and the header-high-nibble masking.
final class PumpingResumedHistoryLogTests: XCTestCase {
    func testPumpingResumedHistoryLog() {
        let expected = PumpingResumedHistoryLog(
            pumpTimeSec: 446032479,
            sequenceNum: 182692,
            preResumeState: 100,
            insulinAmount: 180
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "0c005fea951aa4c9020064000000b40000000000000000000000",
            expected
        )
        XCTAssertEqual(100, parsed.preResumeState)
        XCTAssertEqual(180, parsed.insulinAmount)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testPumpingResumedHistoryLogAfterAlarmSuspend() {
        let expected = PumpingResumedHistoryLog(
            pumpTimeSec: 587315910,
            sequenceNum: 744340,
            preResumeState: 100,
            insulinAmount: 150
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "0c10c6ba0123945b0b0064000000960000000000000000000000",
            expected
        )
        XCTAssertEqual(587315910, parsed.pumpTimeSec)
        XCTAssertEqual(744340, parsed.sequenceNum)
        XCTAssertEqual(100, parsed.preResumeState)
        XCTAssertEqual(150, parsed.insulinAmount)
        MessageTester.assertHexEquals(expected.cargo, PumpingSuspendedHistoryLogTests.withoutSourceNibble(parsed.cargo))
    }

    func testPumpingResumedHistoryLogAfterUserSuspend() {
        let expected = PumpingResumedHistoryLog(
            pumpTimeSec: 587388971,
            sequenceNum: 748806,
            preResumeState: 100,
            insulinAmount: 105
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "0c102bd80223066d0b0064000000690000000000000000000000",
            expected
        )
        XCTAssertEqual(587388971, parsed.pumpTimeSec)
        XCTAssertEqual(748806, parsed.sequenceNum)
        XCTAssertEqual(100, parsed.preResumeState)
        XCTAssertEqual(105, parsed.insulinAmount)
        MessageTester.assertHexEquals(expected.cargo, PumpingSuspendedHistoryLogTests.withoutSourceNibble(parsed.cargo))
    }

    // The two fixtures below were observed on a Tandem Mobi driven by Trio (Control-IQ off, no CGM
    // paired), Sept 2026 BLE capture. In both, `insulinAmount` equalled
    // `InsulinStatusResponse.currentInsulinAmount` polled within two seconds of the resume
    // (pumpX2 issue 40).

    /// Resume after a tubing fill on the same cartridge: the paired suspend recorded 110 units and
    /// the prime brought the reservoir down to 90, which is what the resume reports.
    func testPumpingResumedHistoryLogAfterTubingFill() {
        let expected = PumpingResumedHistoryLog(
            pumpTimeSec: 589585424,
            sequenceNum: 643715,
            preResumeState: 100,
            insulinAmount: 90
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "0c10105c242383d20900640000005a0000000000000000000000",
            expected
        )
        XCTAssertEqual(589585424, parsed.pumpTimeSec)
        XCTAssertEqual(643715, parsed.sequenceNum)
        XCTAssertEqual(100, parsed.preResumeState)
        XCTAssertEqual(90, parsed.insulinAmount)
        MessageTester.assertHexEquals(expected.cargo, PumpingSuspendedHistoryLogTests.withoutSourceNibble(parsed.cargo))
    }

    /// Resume after a cartridge change: the paired suspend recorded 8 units, and the resume reports
    /// the freshly filled 185, equal to `CartridgeFilledHistoryLog.insulinDisplay` in the same
    /// second. Shows the field is the remaining amount rather than a fill level or IOB.
    func testPumpingResumedHistoryLogAfterCartridgeChange() {
        let expected = PumpingResumedHistoryLog(
            pumpTimeSec: 589745836,
            sequenceNum: 651756,
            preResumeState: 100,
            insulinAmount: 185
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "0c10acce2623ecf1090064000000b90000000000000000000000",
            expected
        )
        XCTAssertEqual(589745836, parsed.pumpTimeSec)
        XCTAssertEqual(651756, parsed.sequenceNum)
        XCTAssertEqual(100, parsed.preResumeState)
        XCTAssertEqual(185, parsed.insulinAmount)
        MessageTester.assertHexEquals(expected.cargo, PumpingSuspendedHistoryLogTests.withoutSourceNibble(parsed.cargo))
    }
}
