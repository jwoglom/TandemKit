@testable import TandemKit
import XCTest

final class SetG6TransmitterIdResponseTests: XCTestCase {
    func testSetG6TransmitterIdResponse() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetG6TransmitterIdResponse(status: 0)

        let parsed: SetG6TransmitterIdResponse = MessageTester.test(
            "0021b121190085c3f21f51e3fabfa0a59cd348aed259b44201903b33d9bead20",
            33,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
    }
}
