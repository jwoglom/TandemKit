@testable import TandemKit
import XCTest

final class SoftwareIdHistoryLogTests: XCTestCase {
    func testSoftwareIdMobiDailySlots() {
        // Maintainer's Tandem Mobi (7.9.0.2): one daily block, in the order the pump wrote it.
        let hex = [
            "c11130652c23983c0a0000000000d51ac9d328b2124c00000000",
            "c11130652c23993c0a0002000000d51ac9d328b2124c00000000",
            "c11130652c239a3c0a0001000000d51ac9d328b2124c00000000",
            "c11130652c239b3c0a0003000000d51ac9d328b2124c00000000",
        ]
        let slots = [0, 2, 1, 3]
        for i in 0 ..< hex.count {
            let expected = SoftwareIdHistoryLog(
                pumpTimeSec: 590_112_048,
                sequenceNum: 670_872 + UInt32(i),
                slot: slots[i],
                unknown11: 0,
                armSwVersion: 3_553_172_181,
                softwareIdLow: 1_276_293_672,
                unknown22: 0
            ).withHeaderHighNibble(1)

            let parsed = HistoryLogMessageTester.testSingle(hex[i], expected)
            MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
            XCTAssertEqual(slots[i], parsed.slot)
            XCTAssertEqual(3_553_172_181, parsed.armSwVersion)
            XCTAssertEqual(1_276_293_672, parsed.softwareIdLow)
            XCTAssertTrue(parsed.isSoftwareIdKnown)
            XCTAssertEqual("d3c91ad54c12b228", parsed.softwareId)
            XCTAssertEqual(0, parsed.unknown11)
            XCTAssertEqual(0, parsed.unknown22)
        }
    }

    func testSoftwareIdHighWordIsVersionsAArmSwVersion() {
        // Maintainer's Tandem Mobi (7.9.0.2): the VersionsA record written just before the slots above.
        let versions = HistoryLogParser.parse(Data(hexadecimalString: "331130652c23973c0a00b3870f00d51ac9d3b3870f00d51ac9d3")!) as! VersionsAHistoryLog
        let softwareId = HistoryLogParser.parse(Data(hexadecimalString: "c11130652c23983c0a0000000000d51ac9d328b2124c00000000")!) as! SoftwareIdHistoryLog

        XCTAssertEqual(670_871, versions.sequenceNum)
        XCTAssertEqual(670_872, softwareId.sequenceNum)
        XCTAssertEqual(versions.armSwVersion, softwareId.armSwVersion)
    }

    func testSoftwareIdX2DailySlots() {
        // Maintainer's t:slim X2 (2024), which writes only slots 0 and 2.
        let hex = [
            "c101976ad71f480a1000000000000c1f365cbecffebb00000000",
            "c101976ad71f490a1000020000000c1f365cbecffebb00000000",
        ]
        let slots = [0, 2]
        for i in 0 ..< hex.count {
            let expected = SoftwareIdHistoryLog(
                pumpTimeSec: 534_211_223,
                sequenceNum: 1_051_208 + UInt32(i),
                slot: slots[i],
                armSwVersion: 1_547_050_764,
                softwareIdLow: 3_154_038_718
            )

            let parsed = HistoryLogMessageTester.testSingle(hex[i], expected)
            MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
            XCTAssertEqual(slots[i], parsed.slot)
            XCTAssertEqual("5c361f0cbbfecfbe", parsed.softwareId)
        }
    }

    func testSoftwareIdUnfilledBootSlot() {
        // Maintainer's Tandem Mobi (7.9.0.1): a boot across midnight logs slot 0 before it is filled.
        let expectedUnfilled = SoftwareIdHistoryLog(
            pumpTimeSec: 379_657_371,
            sequenceNum: 42,
            slot: 0,
            armSwVersion: 0,
            softwareIdLow: 0
        ).withHeaderHighNibble(1)

        let unfilled = HistoryLogMessageTester.testSingle("c1119b1ca1162a00000000000000000000000000000000000000", expectedUnfilled)
        MessageTester.assertHexEquals(expectedUnfilled.cargo, unfilled.cargo)
        XCTAssertEqual(0, unfilled.slot)
        XCTAssertFalse(unfilled.isSoftwareIdKnown)
        XCTAssertEqual("", unfilled.softwareId)

        let expectedFilled = SoftwareIdHistoryLog(
            pumpTimeSec: 379_657_372,
            sequenceNum: 48,
            slot: 0,
            armSwVersion: 1_108_201_743,
            softwareIdLow: 390_327_166
        ).withHeaderHighNibble(1)

        let filled = HistoryLogMessageTester.testSingle("c1119c1ca11630000000000000000fd10d427eeb431700000000", expectedFilled)
        MessageTester.assertHexEquals(expectedFilled.cargo, filled.cargo)
        XCTAssertTrue(filled.isSoftwareIdKnown)
        XCTAssertEqual("420dd10f1743eb7e", filled.softwareId)
    }

    func testSoftwareIdX2UnfilledBootSlot() {
        // Maintainer's t:slim X2 (2024).
        let expected = SoftwareIdHistoryLog(
            pumpTimeSec: 505_928_865,
            sequenceNum: 43,
            slot: 0,
            armSwVersion: 0,
            softwareIdLow: 0
        )

        let parsed = HistoryLogMessageTester.testSingle("c101a1dc271e2b00000000000000000000000000000000000000", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertFalse(parsed.isSoftwareIdKnown)
        XCTAssertEqual("", parsed.softwareId)
    }
}
