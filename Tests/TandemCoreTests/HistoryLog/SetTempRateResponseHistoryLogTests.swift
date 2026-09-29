@testable import TandemKit
import XCTest

final class SetTempRateResponseHistoryLogTests: XCTestCase {
    func testAcceptedTempRate() {
        let expected = SetTempRateResponseHistoryLog(
            pumpTimeSec: 591098918,
            sequenceNum: 723593,
            status: 0,
            unknown11: 0,
            tempRateId: 5014
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "351126743b23890a0b0000009613000000000000000000000000",
            expected
        )
        XCTAssertEqual(parsed.status, 0)
        XCTAssertEqual(parsed.tempRateId, 5014)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testRejectedTempRate() {
        let expected = SetTempRateResponseHistoryLog(
            pumpTimeSec: 591099216,
            sequenceNum: 723628,
            status: 1,
            unknown11: 1,
            tempRateId: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "351150753b23ac0a0b0001010000000000000000000000000000",
            expected
        )
        XCTAssertEqual(parsed.status, 1)
        XCTAssertEqual(parsed.unknown11, 1)
        XCTAssertEqual(parsed.tempRateId, 0)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testIssueExample() {
        let expected = SetTempRateResponseHistoryLog(
            pumpTimeSec: 589527121,
            sequenceNum: 640774,
            status: 0,
            unknown11: 0,
            tempRateId: 1815
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "35115178232306c7090000001707000000000000000000000000",
            expected
        )
        XCTAssertEqual(parsed.tempRateId, 1815)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
