@testable import TandemKit
import XCTest

final class SuspendPumpingResponseTests: XCTestCase {
    func testSuspendPumpingResponse() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SuspendPumpingResponse(status: 0)

        let parsed: SuspendPumpingResponse = MessageTester.test(
            "00659d651900e6a3ee1f4114c9f737f36d02bf6794cc45047602f27e1da5996a",
            101,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
    }
}
