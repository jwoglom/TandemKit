@testable import TandemKit
import XCTest

/// SYNTHETIC records at the offsets pumpX2 parses: pumpX2's test is ignored for want of a sample, and
/// no BolexCompleted (21) capture is held here. A pump capture should replace them.
final class BolexCompletedHistoryLogTests: XCTestCase {
    func testBolexCompletedHistoryLogSyntheticCompleted() {
        let expected = BolexCompletedHistoryLog(
            pumpTimeSec: 1000, sequenceNum: 2000, completionStatus: 3, bolusId: 0x1234,
            iob: 2.25, insulinDelivered: 2.25, insulinRequested: 2.25
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "1500e8030000d007000003003412000010400000104000001040",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.completionStatus, 3)
        XCTAssertEqual(parsed.completionStatusEnum, .complete)
        XCTAssertEqual(parsed.bolusId, 0x1234)
        XCTAssertEqual(parsed.iob, 2.25)
        XCTAssertEqual(parsed.insulinDelivered, 2.25)
        XCTAssertEqual(parsed.insulinRequested, 2.25)
    }

    func testBolexCompletedHistoryLogSyntheticStoppedEarly() {
        let expected = BolexCompletedHistoryLog(
            pumpTimeSec: 1000, sequenceNum: 2000, completionStatus: 0, bolusId: 0x1234,
            iob: 0.75, insulinDelivered: 0.75, insulinRequested: 2.25
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "1500e8030000d0070000000034120000403f0000403f00001040",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.completionStatusEnum, .stopped)
        XCTAssertEqual(parsed.insulinDelivered, 0.75)
        XCTAssertEqual(parsed.insulinRequested, 2.25)
    }
}
