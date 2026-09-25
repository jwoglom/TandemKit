@testable import TandemKit
import XCTest

final class BolusDeliverySummaryHistoryLogTests: XCTestCase {
    // Sixth bolus within about an hour: 0.05 + 0.55 + 0.45 + 0.05 + 0.15 + 0.3 U = 1.55 U, i.e. 15.5.
    func testMobiSixthBolusInWindow() {
        let expected = BolusDeliverySummaryHistoryLog(
            pumpTimeSec: 590145454,
            sequenceNum: 672504,
            unknownU8At10: 6,
            unknownU8At11: 27,
            unknownFloatAt14: Float(bitPattern: 0x40400001),
            unknownFloatAt18: Float(bitPattern: 0x40400001),
            unknownFloatAt22: 15.5
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle("c210aee72c23f8420a00061b0000010040400100404000007841", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.unknownU8At10, 6)
        XCTAssertEqual(parsed.unknownU8At11, 27)
        XCTAssertEqual(parsed.unknownFloatAt22, 15.5)
    }

    func testMobiWindowAfterOlderBolusesDropped() {
        let expected = BolusDeliverySummaryHistoryLog(
            pumpTimeSec: 590147253,
            sequenceNum: 672608,
            unknownU8At10: 4,
            unknownU8At11: 29,
            unknownFloatAt14: 0.5,
            unknownFloatAt18: 0.5,
            unknownFloatAt22: 5.5
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle("c210b5ee2c2360430a00041d00000000003f0000003f0000b040", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.unknownU8At10, 4)
    }
}
