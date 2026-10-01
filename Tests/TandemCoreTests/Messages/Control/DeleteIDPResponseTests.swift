@testable import TandemKit
import XCTest

final class DeleteIDPResponseTests: XCTestCase {
    func testDeleteIDPResponse_deleteIdpId2() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = DeleteIDPResponse(status: 0, deletedIdpId: 2)

        let parsed: DeleteIDPResponse = MessageTester.test(
            "004daf4d1a000291033e208345bb76cb9e5327ede6e87a0e590223f1ab75c1f93d",
            77,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
        XCTAssertEqual(2, parsed.deletedIdpId)
    }

    func testDeleteIDPResponse_deleteIdpId1() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = DeleteIDPResponse(status: 0, deletedIdpId: 2)

        let parsed: DeleteIDPResponse = MessageTester.test(
            "0053af531a0002a0033e20d85eaa5d3690b58e62edeac041a420ef93de1bdda8bf",
            83,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
        XCTAssertEqual(2, parsed.deletedIdpId)
    }
}
