@testable import TandemKit
import XCTest

final class ControlRequestCountersHistoryLogTests: XCTestCase {
    func testControlRequestCountersMobi() {
        // Maintainer's Tandem Mobi; 35 CONTROL requests in the two hours before, one of them a DismissNotificationRequest.
        let expected = ControlRequestCountersHistoryLog(
            pumpTimeSec: 590119274,
            sequenceNum: 671193,
            controlRequestCount: 35,
            unknown14: 0,
            unknown18: 34,
            unknown22: 1
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "ec116a812c23d93d0a0023000000000000002200000001000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(35, parsed.controlRequestCount)
        XCTAssertEqual(parsed.controlRequestCount, parsed.unknown18 + parsed.unknown22)
    }

    func testControlRequestCountersIssueExample() {
        let expected = ControlRequestCountersHistoryLog(
            pumpTimeSec: 589528874,
            sequenceNum: 640829,
            controlRequestCount: 37,
            unknown14: 0,
            unknown18: 34,
            unknown22: 3
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "ec112a7f23233dc7090025000000000000002200000003000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.controlRequestCount, parsed.unknown18 + parsed.unknown22)
    }

    func testControlRequestCountersIssueExampleCharging() {
        let expected = ControlRequestCountersHistoryLog(
            pumpTimeSec: 589557674,
            sequenceNum: 642149,
            controlRequestCount: 40,
            unknown14: 0,
            unknown18: 31,
            unknown22: 9
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "ec11aaef232365cc090028000000000000001f00000009000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.controlRequestCount, parsed.unknown18 + parsed.unknown22)
    }
}
