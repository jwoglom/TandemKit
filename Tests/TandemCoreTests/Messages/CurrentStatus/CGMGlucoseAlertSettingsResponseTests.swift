import XCTest
@testable import TandemCore

final class CGMGlucoseAlertSettingsResponseTests: XCTestCase {
    func testCGMGlucoseAlertSettingsResponseHigh200Low80Hourly() {
        let expected = CGMGlucoseAlertSettingsResponse(
            highGlucoseAlertThreshold: 200,
            highGlucoseAlertEnabled: 1,
            highGlucoseRepeatDuration: 60,
            highGlucoseAlertDefaultBitmask: 5,
            lowGlucoseAlertThreshold: 80,
            lowGlucoseAlertEnabled: 1,
            lowGlucoseRepeatDuration: 30,
            lowGlucoseAlertDefaultBitmask: 5
        )

        let parsed: CGMGlucoseAlertSettingsResponse = MessageTester.test(
            "00035b030cc800013c00055000011e00052a58",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        assertMatches(parsed, expected)
    }

    func testCGMGlucoseAlertSettingsResponseHighDisabledLow80() {
        let expected = CGMGlucoseAlertSettingsResponse(
            highGlucoseAlertThreshold: 200,
            highGlucoseAlertEnabled: 0,
            highGlucoseRepeatDuration: 60,
            highGlucoseAlertDefaultBitmask: 1,
            lowGlucoseAlertThreshold: 80,
            lowGlucoseAlertEnabled: 1,
            lowGlucoseRepeatDuration: 30,
            lowGlucoseAlertDefaultBitmask: 5
        )

        let parsed: CGMGlucoseAlertSettingsResponse = MessageTester.test(
            "00045b040cc800003c00015000011e0005af86",
            4,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        assertMatches(parsed, expected)
    }

    func testCGMGlucoseAlertSettingsResponseHighNeverRepeatLow80() {
        let expected = CGMGlucoseAlertSettingsResponse(
            highGlucoseAlertThreshold: 200,
            highGlucoseAlertEnabled: 1,
            highGlucoseRepeatDuration: 0,
            highGlucoseAlertDefaultBitmask: 1,
            lowGlucoseAlertThreshold: 80,
            lowGlucoseAlertEnabled: 1,
            lowGlucoseRepeatDuration: 30,
            lowGlucoseAlertDefaultBitmask: 5
        )

        let parsed: CGMGlucoseAlertSettingsResponse = MessageTester.test(
            "00055b050cc800010000015000011e000599d3",
            5,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        assertMatches(parsed, expected)
    }

    func testCGMGlucoseAlertSettingsResponseHigh250Low80() {
        let expected = CGMGlucoseAlertSettingsResponse(
            highGlucoseAlertThreshold: 250,
            highGlucoseAlertEnabled: 1,
            highGlucoseRepeatDuration: 300,
            highGlucoseAlertDefaultBitmask: 0,
            lowGlucoseAlertThreshold: 80,
            lowGlucoseAlertEnabled: 1,
            lowGlucoseRepeatDuration: 30,
            lowGlucoseAlertDefaultBitmask: 5
        )

        let parsed: CGMGlucoseAlertSettingsResponse = MessageTester.test(
            "00065b060cfa00012c01005000011e00057eec",
            6,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        assertMatches(parsed, expected)
    }

    func testCGMGlucoseAlertSettingsResponseHigh120Low80() {
        let expected = CGMGlucoseAlertSettingsResponse(
            highGlucoseAlertThreshold: 120,
            highGlucoseAlertEnabled: 1,
            highGlucoseRepeatDuration: 300,
            highGlucoseAlertDefaultBitmask: 0,
            lowGlucoseAlertThreshold: 80,
            lowGlucoseAlertEnabled: 1,
            lowGlucoseRepeatDuration: 30,
            lowGlucoseAlertDefaultBitmask: 5
        )

        let parsed: CGMGlucoseAlertSettingsResponse = MessageTester.test(
            "00075b070c7800012c01005000011e0005543b",
            7,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        assertMatches(parsed, expected)
    }

    private func assertMatches(_ parsed: CGMGlucoseAlertSettingsResponse, _ expected: CGMGlucoseAlertSettingsResponse) {
        XCTAssertEqual(expected.highGlucoseAlertThreshold, parsed.highGlucoseAlertThreshold)
        XCTAssertEqual(expected.highGlucoseAlertEnabled, parsed.highGlucoseAlertEnabled)
        XCTAssertEqual(expected.highGlucoseRepeatDuration, parsed.highGlucoseRepeatDuration)
        XCTAssertEqual(expected.highGlucoseAlertDefaultBitmask, parsed.highGlucoseAlertDefaultBitmask)
        XCTAssertEqual(expected.lowGlucoseAlertThreshold, parsed.lowGlucoseAlertThreshold)
        XCTAssertEqual(expected.lowGlucoseAlertEnabled, parsed.lowGlucoseAlertEnabled)
        XCTAssertEqual(expected.lowGlucoseRepeatDuration, parsed.lowGlucoseRepeatDuration)
        XCTAssertEqual(expected.lowGlucoseAlertDefaultBitmask, parsed.lowGlucoseAlertDefaultBitmask)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
