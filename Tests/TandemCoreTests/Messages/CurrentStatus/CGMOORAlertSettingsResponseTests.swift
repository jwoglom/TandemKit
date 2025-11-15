import XCTest
@testable import TandemCore

final class CGMOORAlertSettingsResponseTests: XCTestCase {
    func testCGMOORAlertSettingsResponse() {
        let expected = CGMOORAlertSettingsResponse(
            sensorTimeoutAlertThreshold: 20,
            sensorTimeoutAlertEnabled: 1,
            sensorTimeoutDefaultBitmask: 5
        )

        let parsed: CGMOORAlertSettingsResponse = MessageTester.test(
            "00035f0303140105be32",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(expected.sensorTimeoutAlertThreshold, parsed.sensorTimeoutAlertThreshold)
        XCTAssertEqual(expected.sensorTimeoutAlertEnabled, parsed.sensorTimeoutAlertEnabled)
        XCTAssertEqual(expected.sensorTimeoutDefaultBitmask, parsed.sensorTimeoutDefaultBitmask)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
