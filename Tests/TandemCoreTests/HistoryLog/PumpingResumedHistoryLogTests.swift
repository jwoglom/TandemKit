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
}
