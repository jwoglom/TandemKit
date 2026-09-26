@testable import TandemKit
import XCTest

final class ControlIQFeaturesHistoryLogTests: XCTestCase {
    func testControlIQFeaturesX2Api25UnsupportedIsZero() {
        // Maintainer's t:slim X2 (API 2.5), daily block. Header high nibble 0.
        let expected = ControlIQFeaturesHistoryLog(
            pumpTimeSec: 461462412,
            sequenceNum: 23511,
            controlIqFeaturesBitmask: 0
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "48018c5b811bd75b000000000000000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.controlIqFeaturesBitmask)
        XCTAssertTrue(parsed.controlIqFeatures.isEmpty)
        XCTAssertEqual(Data(count: 12), parsed.unknownTail)
    }

    func testControlIQFeaturesX2FirstBootAfterFirmwareUpdate() {
        // Maintainer's t:slim X2, first boot on API 3.2 firmware. Header high nibble 0.
        let expected = ControlIQFeaturesHistoryLog(
            pumpTimeSec: 503757902,
            sequenceNum: 2107760,
            controlIqFeaturesBitmask: 49
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "48014ebc061e7029200031000000000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(49, parsed.controlIqFeaturesBitmask)
    }

    func testControlIQFeaturesX2Api34Daily() {
        // Maintainer's t:slim X2 (API 3.4), daily block. Header high nibble 0.
        let expected = ControlIQFeaturesHistoryLog(
            pumpTimeSec: 534211223,
            sequenceNum: 1051211,
            controlIqFeaturesBitmask: 49
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "4801976ad71f4b0a100031000000000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(49, parsed.controlIqFeaturesBitmask)
        XCTAssertEqual([.timedExercise], parsed.controlIqFeatures)
        XCTAssertEqual(0x30, parsed.controlIqFeaturesBitmask & 0x30)
    }

    func testControlIQFeaturesMobi7701Boot() {
        // Maintainer's Tandem Mobi (7.7.0.1). Header high nibble 1.
        let expected = ControlIQFeaturesHistoryLog(
            pumpTimeSec: 539917225,
            sequenceNum: 122684,
            controlIqFeaturesBitmask: 3072
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "4811a97b2e203cdf0100000c0000000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(3072, parsed.controlIqFeaturesBitmask)
        XCTAssertEqual([.extendedBolusEnabled], parsed.controlIqFeatures)
        XCTAssertEqual(0x400, parsed.controlIqFeaturesBitmask & 0x400)
    }

    func testControlIQFeaturesMobiFirstBootOn7901() {
        // Maintainer's Tandem Mobi (7.9.0.1), first boot after updating from 7.7.0.1. Header high nibble 1.
        let expected = ControlIQFeaturesHistoryLog(
            pumpTimeSec: 552609115,
            sequenceNum: 614874,
            controlIqFeaturesBitmask: 896
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "48115b25f020da61090080030000000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(896, parsed.controlIqFeaturesBitmask)
    }

    func testControlIQFeaturesMobi7902Daily() {
        // Maintainer's Tandem Mobi (7.9.0.2), daily block. Header high nibble 1.
        let expected = ControlIQFeaturesHistoryLog(
            pumpTimeSec: 590112048,
            sequenceNum: 670877,
            controlIqFeaturesBitmask: 896
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "481130652c239d3c0a0080030000000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(896, parsed.controlIqFeaturesBitmask)
        XCTAssertEqual([.controlIqVersionOneFive, .tempRateEnabled], parsed.controlIqFeatures)
        XCTAssertEqual(0x80, parsed.controlIqFeaturesBitmask & 0x80)
        XCTAssertEqual(Data(count: 12), parsed.unknownTail)
    }
}
