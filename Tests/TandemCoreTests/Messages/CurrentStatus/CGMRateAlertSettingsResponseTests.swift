@testable import TandemCore
import XCTest

final class CGMRateAlertSettingsResponseTests: XCTestCase {
    func testCGMRateAlertSettingsResponse() {
        let expected = CGMRateAlertSettingsResponse(
            riseRateThreshold: 3,
            riseRateEnabled: 1,
            riseRateDefaultBitmask: 1,
            fallRateThreshold: 3,
            fallRateEnabled: 1,
            fallRateDefaultBitmask: 1
        )

        let parsed: CGMRateAlertSettingsResponse = MessageTester.test(
            "00045d04060301010301016b8c",
            4,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        assertMatches(parsed, expected)
    }

    func testCGMRateAlertSettingsResponseFallRateDisabled() {
        let expected = CGMRateAlertSettingsResponse(
            riseRateThreshold: 3,
            riseRateEnabled: 1,
            riseRateDefaultBitmask: 1,
            fallRateThreshold: 2,
            fallRateEnabled: 1,
            fallRateDefaultBitmask: 0
        )

        let parsed: CGMRateAlertSettingsResponse = MessageTester.test(
            "00055d0506030101020100a9ec",
            5,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        assertMatches(parsed, expected)
    }

    private func assertMatches(_ parsed: CGMRateAlertSettingsResponse, _ expected: CGMRateAlertSettingsResponse) {
        XCTAssertEqual(expected.riseRateThreshold, parsed.riseRateThreshold)
        XCTAssertEqual(expected.riseRateEnabled, parsed.riseRateEnabled)
        XCTAssertEqual(expected.riseRateDefaultBitmask, parsed.riseRateDefaultBitmask)
        XCTAssertEqual(expected.fallRateThreshold, parsed.fallRateThreshold)
        XCTAssertEqual(expected.fallRateEnabled, parsed.fallRateEnabled)
        XCTAssertEqual(expected.fallRateDefaultBitmask, parsed.fallRateDefaultBitmask)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
