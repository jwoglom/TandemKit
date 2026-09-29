@testable import TandemKit
import XCTest

final class AuthorizationCountersHistoryLogTests: XCTestCase {
    func testAuthorizationCountersThreeReconnects() {
        // Maintainer's Tandem Mobi; three JPAKE reconnects (3 Jpake3 + 3 Jpake4 responses) in the two hours before.
        let expected = AuthorizationCountersHistoryLog(
            pumpTimeSec: 590119270,
            sequenceNum: 671183,
            authorizationRequestCount: 6,
            unknown14: 0,
            unknown18: 0,
            unknown22: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "ee1166812c23cf3d0a0006000000000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(6, parsed.authorizationRequestCount)
    }

    func testAuthorizationCountersIssueExampleZero() {
        let expected = AuthorizationCountersHistoryLog(
            pumpTimeSec: 589528867,
            sequenceNum: 640819,
            authorizationRequestCount: 0,
            unknown14: 0,
            unknown18: 0,
            unknown22: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "ee11237f232333c7090000000000000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.authorizationRequestCount)
    }
}
