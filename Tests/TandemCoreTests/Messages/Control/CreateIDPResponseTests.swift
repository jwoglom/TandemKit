@testable import TandemKit
import XCTest

final class CreateIDPResponseTests: XCTestCase {
    func testCreateNewIDPResponse() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = CreateIDPResponse(status: 0, newIdpId: 2)

        let parsed: CreateIDPResponse = MessageTester.test(
            "00c9e7c91a000286023e203400da47812a7ab10adc5f006d21fda44a7d7afa907b",
            -55,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
        XCTAssertEqual(2, parsed.newIdpId)
    }

    func testCreateIDPResponse_duplicate1() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = CreateIDPResponse(cargo: Data([0x00, 0x02]))

        let parsed: CreateIDPResponse = MessageTester.test(
            "0037e7371a000281033e20e6b4f3960cd57ac9d1d4d84e18cd1571588aa0cf4281",
            55,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
