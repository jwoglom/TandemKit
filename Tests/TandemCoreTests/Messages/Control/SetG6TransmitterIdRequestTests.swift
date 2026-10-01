@testable import TandemKit
import XCTest

final class SetG6TransmitterIdRequestTests: XCTestCase {
    func testSetG6TransmitterIdRequest_8L459R() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetG6TransmitterIdRequest(txId: "8L459R")

        let parsed: SetG6TransmitterIdRequest = MessageTester.test(
            "0221b02128384c34353952000000000000000000",
            33,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "012100da09f31f74a5fbd08dc7fc210ddd3cb101",
            "00218f1dc87134edb724ae"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual("8L459R", parsed.txId)
    }
}
