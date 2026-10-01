@testable import TandemKit
import XCTest

final class ResumePumpingResponseTests: XCTestCase {
    func testResumePumpingResponse() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = ResumePumpingResponse(status: 0)

        let parsed: ResumePumpingResponse = MessageTester.test(
            "003d9b3d1900b5a3ee1f16c41eadee9847ab861cd24604a11e4a68d0a7dd2abe",
            61,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
    }
}
