@testable import TandemKit
import XCTest

final class MaxBolusLimitSetHistoryLogTests: XCTestCase {
    func testMaxBolusLimitSetMobiSameValue() {
        // Maintainer's Tandem Mobi, for a SetMaxBolusLimitRequest that re-sent the current 15000.
        let expected = MaxBolusLimitSetHistoryLog(
            pumpTimeSec: 590188136,
            sequenceNum: 674692,
            maxBolusMilliunits: 15000,
            previousMaxBolusMilliunits: 15000
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "4611688e2d23844b0a00983a983a000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(15000, parsed.maxBolusMilliunits)
        XCTAssertEqual(15000, parsed.previousMaxBolusMilliunits)
    }

    func testMaxBolusLimitSetTslimX2Change() {
        // Maintainer's t:slim X2: 10000 -> 25000.
        let expected = MaxBolusLimitSetHistoryLog(
            pumpTimeSec: 505928913,
            sequenceNum: 70,
            maxBolusMilliunits: 25000,
            previousMaxBolusMilliunits: 10000
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "4601d1dc271e46000000a8611027000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(25000, parsed.maxBolusMilliunits)
        XCTAssertEqual(10000, parsed.previousMaxBolusMilliunits)
    }
}
