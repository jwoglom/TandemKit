@testable import TandemKit
import XCTest

final class BleSoftDeviceVersionHistoryLogTests: XCTestCase {
    private func assertVersion720(_ log: BleSoftDeviceVersionHistoryLog, file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(log.isKnown, file: file, line: line)
        XCTAssertEqual(132, log.softDeviceId, file: file, line: line)
        XCTAssertEqual(7, log.softDeviceMajorVersion, file: file, line: line)
        XCTAssertEqual(2, log.softDeviceMinorVersion, file: file, line: line)
        XCTAssertEqual(0, log.softDeviceBugfixVersion, file: file, line: line)
        XCTAssertEqual(132, log.softDeviceId2, file: file, line: line)
        XCTAssertEqual(7, log.softDeviceMajorVersion2, file: file, line: line)
        XCTAssertEqual(2, log.softDeviceMinorVersion2, file: file, line: line)
        XCTAssertEqual(0, log.softDeviceBugfixVersion2, file: file, line: line)
        XCTAssertEqual("7.2.0", log.versionString, file: file, line: line)
        XCTAssertEqual("7.2.0", log.versionString2, file: file, line: line)
    }

    private func version720(pumpTimeSec: UInt32, sequenceNum: UInt32) -> BleSoftDeviceVersionHistoryLog {
        BleSoftDeviceVersionHistoryLog(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            softDeviceId: 132,
            softDeviceMajorVersion: 7,
            softDeviceMinorVersion: 2,
            softDeviceBugfixVersion: 0,
            softDeviceId2: 132,
            softDeviceMajorVersion2: 7,
            softDeviceMinorVersion2: 2,
            softDeviceBugfixVersion2: 0
        )
    }

    func testBleSoftDeviceVersionX2MidnightBlock() {
        // Maintainer's t:slim X2 (2024). Header high nibble 0.
        let expected = version720(pumpTimeSec: 534211223, sequenceNum: 1051210)

        let parsed = HistoryLogMessageTester.testSingle(
            "c201976ad71f4a0a100084000700020000008400070002000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertVersion720(parsed)
    }

    func testBleSoftDeviceVersionX2FirstBootAfterFirmwareUpdate() {
        // Maintainer's t:slim X2 (2023). Header high nibble 0.
        let expected = version720(pumpTimeSec: 503757910, sequenceNum: 2107772)

        let parsed = HistoryLogMessageTester.testSingle(
            "c20156bc061e7c29200084000700020000008400070002000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertVersion720(parsed)
    }

    func testBleSoftDeviceVersionMobiMidnightBlock() {
        // Maintainer's Tandem Mobi (7.9.0.2). Header high nibble 1.
        let expected = version720(pumpTimeSec: 590112048, sequenceNum: 670876).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "c21130652c239c3c0a0084000700020000008400070002000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertVersion720(parsed)
    }

    func testBleSoftDeviceVersionMobiBootAfterFirmwareUpdate() {
        // Maintainer's Tandem Mobi (7.9.0.2). Header high nibble 1.
        let expected = version720(pumpTimeSec: 564414486, sequenceNum: 423427).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "c2111648a4210376060084000700020000008400070002000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertVersion720(parsed)
    }

    func testBleSoftDeviceVersionMobiAllZeroDuringBoot() {
        // Maintainer's Tandem Mobi (7.9.0.1), clock not yet set. Header high nibble 1.
        let expected = BleSoftDeviceVersionHistoryLog(
            pumpTimeSec: 379657371,
            sequenceNum: 46,
            softDeviceId: 0,
            softDeviceMajorVersion: 0,
            softDeviceMinorVersion: 0,
            softDeviceBugfixVersion: 0,
            softDeviceId2: 0,
            softDeviceMajorVersion2: 0,
            softDeviceMinorVersion2: 0,
            softDeviceBugfixVersion2: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "c2119b1ca1162e00000000000000000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertFalse(parsed.isKnown)
        XCTAssertEqual(0, parsed.softDeviceId)
        XCTAssertEqual(0, parsed.softDeviceId2)
        XCTAssertNil(parsed.versionString)
        XCTAssertNil(parsed.versionString2)
    }

    func testBleSoftDeviceVersionMobiFilledInThreeSecondsLater() {
        // Maintainer's Tandem Mobi (7.9.0.1), same boot as the all-zero record. Header high nibble 1.
        let expected = version720(pumpTimeSec: 379657374, sequenceNum: 66).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "c2119e1ca1164200000084000700020000008400070002000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        assertVersion720(parsed)
        XCTAssertEqual(3, parsed.pumpTimeSec - 379657371)
    }
}
