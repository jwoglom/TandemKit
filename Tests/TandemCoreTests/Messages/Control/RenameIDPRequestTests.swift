@testable import TandemCore
import XCTest

final class RenameIDPRequestTests: XCTestCase {
    func testRenameIDPRequest() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = RenameIDPRequest(idpId: 1, profileName: "testprofil2")

        let parsed: RenameIDPRequest = MessageTester.test(
            "02d6a8d62b01017465737470726f66696c320000",
            -42,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "01d600000000e4483e2065ee618e7bd6a980f0a6",
            "00d60656ac383c1140bccf5a20be"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
