@testable import TandemKit
import XCTest

final class BleLinkStatsHistoryLogTests: XCTestCase {
    func testBleLinkStatsIssueExample() {
        // Maintainer's Tandem Mobi.
        let expected = BleLinkStatsHistoryLog(
            pumpTimeSec: 589528867,
            sequenceNum: 640818,
            minimum: -86,
            maximum: -49,
            unknown12: -64,
            unknown13: -70,
            unknown14: -65,
            unknown15: -60,
            unknown16: 56,
            unknown18: 1835,
            intervalSeconds: 3600
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "d911237f232332c70900aacfc0babfc438002b07100e00000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(-86, parsed.minimum)
        XCTAssertEqual(-49, parsed.maximum)
        XCTAssertEqual(3600, parsed.intervalSeconds)
    }

    func testBleLinkStatsOrderedStatistics() {
        let expected = BleLinkStatsHistoryLog(
            pumpTimeSec: 590112070,
            sequenceNum: 670882,
            minimum: -92,
            maximum: -51,
            unknown12: -73,
            unknown13: -80,
            unknown14: -75,
            unknown15: -70,
            unknown16: 54,
            unknown18: 2264,
            intervalSeconds: 3600
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "d91146652c23a23c0a00a4cdb7b0b5ba3600d808100e00000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertLessThanOrEqual(parsed.minimum, parsed.unknown13)
        XCTAssertLessThanOrEqual(parsed.unknown13, parsed.unknown12)
        XCTAssertLessThanOrEqual(parsed.unknown12, parsed.unknown15)
        XCTAssertLessThanOrEqual(parsed.unknown15, parsed.maximum)
    }

    func testBleLinkStatsIntervalOneSecondLong() {
        // 3600 s of pump time after the previous 473 record.
        let expected = BleLinkStatsHistoryLog(
            pumpTimeSec: 590184070,
            sequenceNum: 674456,
            minimum: -89,
            maximum: -52,
            unknown12: -68,
            unknown13: -75,
            unknown14: -70,
            unknown15: -65,
            unknown16: 43,
            unknown18: 2448,
            intervalSeconds: 3601
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "d911867e2d23984a0a00a7ccbcb5babf2b009009110e00000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(3601, parsed.intervalSeconds)
    }

    func testBleLinkStatsIntervalOneSecondShort() {
        let expected = BleLinkStatsHistoryLog(
            pumpTimeSec: 590187670,
            sequenceNum: 674672,
            minimum: -88,
            maximum: -53,
            unknown12: -68,
            unknown13: -75,
            unknown14: -70,
            unknown15: -65,
            unknown16: 42,
            unknown18: 2505,
            intervalSeconds: 3599
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "d911968c2d23704b0a00a8cbbcb5babf2a00c9090f0e00000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(3599, parsed.intervalSeconds)
    }
}
