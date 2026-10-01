@testable import TandemKit
import XCTest

final class FillCannulaResponseTests: XCTestCase {
    func testFillCannulaResponse_ok() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = FillCannulaResponse(status: 0)

        let parsed: FillCannulaResponse = MessageTester.test(
            "006d996d1900d4ce2720d38b10afb8f57ab650c6682172ef1f0af1e8d4e59e0c",
            109,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
    }
}
