@testable import TandemKit
import XCTest

final class InitiateBolusResponseHistoryLogTests: XCTestCase {
    func testMobiBolusAccepted() {
        let expected = InitiateBolusResponseHistoryLog(
            pumpTimeSec: 589529231, sequenceNum: 640852, bolusId: 2904, unknownU8At14: 0, unknownU8At15: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle("2a118f80232354c70900580b0000000000000000000000000000", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.bolusId, 2904)
    }

    // The captured InitiateBolusResponse was status 1, statusTypeId 2.
    func testX2BolusRejected() {
        let expected = InitiateBolusResponseHistoryLog(
            pumpTimeSec: 463684121, sequenceNum: 58327, bolusId: 10681, unknownU8At14: 2, unknownU8At15: 1
        )

        let parsed = HistoryLogMessageTester.testSingle("2a011942a31bd7e30000b9290000020100000000000000000000", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.unknownU8At14, 2)
        XCTAssertEqual(parsed.unknownU8At15, 1)
    }
}
