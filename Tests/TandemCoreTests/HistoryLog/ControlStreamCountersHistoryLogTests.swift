@testable import TandemKit
import XCTest

final class ControlStreamCountersHistoryLogTests: XCTestCase {
    func testControlStreamCountersCartridgeChange() {
        // Maintainer's Tandem Mobi; 19 CONTROL_STREAM notifications during a cartridge change in the two hours before.
        let expected = ControlStreamCountersHistoryLog(
            pumpTimeSec: 590443275,
            sequenceNum: 689216,
            controlStreamMessageCount: 19,
            unknown14: 0,
            unknown18: 19,
            unknown22: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "ed110b73312340840a0013000000000000001300000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(19, parsed.controlStreamMessageCount)
    }

    func testControlStreamCountersIssueExampleZero() {
        let expected = ControlStreamCountersHistoryLog(
            pumpTimeSec: 589528874,
            sequenceNum: 640830,
            controlStreamMessageCount: 0,
            unknown14: 0,
            unknown18: 0,
            unknown22: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "ed112a7f23233ec7090000000000000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.controlStreamMessageCount)
    }
}
