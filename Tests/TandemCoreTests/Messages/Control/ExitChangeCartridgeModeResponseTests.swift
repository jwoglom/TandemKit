@testable import TandemKit
import XCTest

final class ExitChangeCartridgeModeResponseTests: XCTestCase {
    func testExitChangeCartridgeModeResponse() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = ExitChangeCartridgeModeResponse(status: 0)

        let parsed: ExitChangeCartridgeModeResponse = MessageTester.test(
            "00899389190078c840201a521d880f1dfa4fd153a975571060d9098181614321",
            -119,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
    }
}
