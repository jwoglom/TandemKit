@testable import TandemKit
import XCTest

final class BolusIobEntryHistoryLogTests: XCTestCase {
    func testMobiBolus() {
        let expected = BolusIobEntryHistoryLog(
            pumpTimeSec: 589529251,
            sequenceNum: 640857,
            unknownU8At10: 0,
            unknownU8At11: 4,
            insulinDurationMillis: 18_000_000,
            insulinDelivered: Float(bitPattern: 0x3e4ccccd),
            mudaliarIob: Float(bitPattern: 0x3f731a58)
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle("c310a380232359c709000004000080a81201cdcc4c3e581a733f", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.unknownU8At11, 4)
        XCTAssertEqual(parsed.insulinDurationMillis, 18_000_000)
        XCTAssertEqual(parsed.insulinDelivered.bitPattern, 0x3e4ccccd)
    }

    func testX2EightHourInsulinDuration() {
        let expected = BolusIobEntryHistoryLog(
            pumpTimeSec: 461510714,
            sequenceNum: 24321,
            unknownU8At10: 0,
            unknownU8At11: 0,
            insulinDurationMillis: 28_800_000,
            insulinDelivered: 1.0,
            mudaliarIob: 1.0
        )

        let parsed = HistoryLogMessageTester.testSingle("c3003a18821b015f0000000000000074b7010000803f0000803f", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.insulinDurationMillis, 28_800_000)
    }

    func testX2NothingDelivered() {
        let expected = BolusIobEntryHistoryLog(
            pumpTimeSec: 461638673,
            sequenceNum: 26934,
            unknownU8At10: 1,
            unknownU8At11: 0xFF,
            insulinDurationMillis: 0xFFFF_FFFF,
            insulinDelivered: 0,
            mudaliarIob: 0
        )

        let parsed = HistoryLogMessageTester.testSingle("c300110c841b3669000001ff0000ffffffff0000000000000000", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.unknownU8At10, 1)
        XCTAssertEqual(parsed.unknownU8At11, 0xFF)
    }
}
