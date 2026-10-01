@testable import TandemKit
import XCTest

final class SetActiveIDPResponseTests: XCTestCase {
    func testSetActiveIDPResponse_success() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetActiveIDPResponse(status: 0)

        let parsed: SetActiveIDPResponse = MessageTester.test(
            "0019ed19190036033e20eb7b1d7dc0f2aad134ccab6029516c36a4d910b55778",
            25,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
    }
}
