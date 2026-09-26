@testable import TandemKit
import XCTest

final class PumpDriveEventHistoryLogTests: XCTestCase {
    // Start and end of a 1.5 U bolus: 666882 - 665316 = 1566 = 1.45 U x 1080 counts.
    func testMobiBolusStartAndEnd() {
        let start = PumpDriveEventHistoryLog(
            pumpTimeSec: 590115449, sequenceNum: 670998, driveCounter: 665316,
            unknownI16At14: 45, unknownI16At16: 45, unknownU8At18: 0x64, unknownU8At19: 4,
            unknownU8At20: 2, unknownU8At21: 15, unknownU16At22: 0xFFFF, unknownU16At24: 7
        ).withHeaderHighNibble(1)
        let parsedStart = HistoryLogMessageTester.testSingle("151179722c23163d0a00e4260a002d002d006404020fffff0700", start)
        MessageTester.assertHexEquals(start.cargo, parsedStart.cargo)

        let end = PumpDriveEventHistoryLog(
            pumpTimeSec: 590115492, sequenceNum: 671010, driveCounter: 666882,
            unknownI16At14: 54, unknownI16At16: 54, unknownU8At18: 0x64, unknownU8At19: 4,
            unknownU8At20: 2, unknownU8At21: 15, unknownU16At22: 0xFFFF, unknownU16At24: 12
        ).withHeaderHighNibble(1)
        let parsedEnd = HistoryLogMessageTester.testSingle("1511a4722c23223d0a00022d0a00360036006404020fffff0c00", end)
        MessageTester.assertHexEquals(end.cargo, parsedEnd.cargo)
        XCTAssertEqual(parsedEnd.driveCounter - parsedStart.driveCounter, 1566)
    }

    func testMobiRetraction() {
        let expected = PumpDriveEventHistoryLog(
            pumpTimeSec: 590440357, sequenceNum: 689006, driveCounter: 556233,
            unknownI16At14: -1999, unknownI16At16: -2000, unknownU8At18: 0xC4, unknownU8At19: 4,
            unknownU8At20: 2, unknownU8At21: 15, unknownU16At22: 441, unknownU16At24: 73
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle("1511a56731236e830a00c97c080031f830f8c404020fb9014900", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.unknownI16At14, -1999)
        XCTAssertEqual(parsed.unknownI16At16, -2000)
    }

    func testMobiFill() {
        let expected = PumpDriveEventHistoryLog(
            pumpTimeSec: 590440428, sequenceNum: 689022, driveCounter: 524873,
            unknownI16At14: 298, unknownI16At16: 300, unknownU8At18: 0x64, unknownU8At19: 4,
            unknownU8At20: 2, unknownU8At21: 15, unknownU16At22: 0xFFFF, unknownU16At24: 14
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle("1511ec6731237e830a00490208002a012c016404020fffff0e00", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.driveCounter, 524873)
    }
}
