@testable import TandemKit
import XCTest

final class MaxBasalLimitSetHistoryLogTests: XCTestCase {
    func testMaxBasalLimitSetMobiSameValue() {
        // Maintainer's Tandem Mobi, for a SetMaxBasalLimitRequest that re-sent the current 4000.
        let expected = MaxBasalLimitSetHistoryLog(
            pumpTimeSec: 590188136,
            sequenceNum: 674689,
            maxHourlyBasalMilliunits: 4000,
            previousMaxHourlyBasalMilliunits: 4000
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "1211688e2d23814b0a00a00f0000a00f00000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(4000, parsed.maxHourlyBasalMilliunits)
        XCTAssertEqual(4000, parsed.previousMaxHourlyBasalMilliunits)
    }

    func testMaxBasalLimitSetTslimX2Change() {
        // Maintainer's t:slim X2: 3000 -> 5000.
        let expected = MaxBasalLimitSetHistoryLog(
            pumpTimeSec: 505928913,
            sequenceNum: 71,
            maxHourlyBasalMilliunits: 5000,
            previousMaxHourlyBasalMilliunits: 3000
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "1201d1dc271e4700000088130000b80b00000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(5000, parsed.maxHourlyBasalMilliunits)
        XCTAssertEqual(3000, parsed.previousMaxHourlyBasalMilliunits)
    }
}
