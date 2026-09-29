@testable import TandemKit
import XCTest

final class HistoryRequestCountersHistoryLogTests: XCTestCase {
    func testHistoryRequestCountersMobi() {
        // Maintainer's Tandem Mobi; TandemKit sent 27 HistoryLogRequests in the two hours before.
        let expected = HistoryRequestCountersHistoryLog(
            pumpTimeSec: 590119266,
            sequenceNum: 671180,
            historyLogRequestCount: 27,
            unknown14: 0,
            unknown18: 8970,
            unknown22: 280
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "ea1162812c23cc3d0a001b000000000000000a23000018010000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(27, parsed.historyLogRequestCount)
    }

    func testHistoryRequestCountersIssueExample() {
        let expected = HistoryRequestCountersHistoryLog(
            pumpTimeSec: 589528866,
            sequenceNum: 640816,
            historyLogRequestCount: 34,
            unknown14: 0,
            unknown18: 6665,
            unknown22: 198
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "ea11227f232330c709002200000000000000091a0000c6000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
