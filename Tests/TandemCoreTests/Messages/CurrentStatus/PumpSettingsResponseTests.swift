@testable import TandemKit
import XCTest

final class PumpSettingsResponseTests: XCTestCase {
    func testPumpSettingsResponse() {
        let expected = PumpSettingsResponse(
            lowInsulinThreshold: 35,
            cannulaPrimeSize: 30,
            autoShutdownEnabled: 1,
            autoShutdownDuration: 18,
            featureLock: 0,
            oledTimeout: 120,
            status: 93
        )

        let parsed: PumpSettingsResponse = MessageTester.test(
            "0003530309231e01120000785d00703f",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(parsed.lowInsulinThreshold, 35)
        XCTAssertEqual(parsed.autoShutdownDuration, 18)
        XCTAssertEqual(parsed.oledTimeout, 120)
        XCTAssertEqual(parsed.status, 93)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
