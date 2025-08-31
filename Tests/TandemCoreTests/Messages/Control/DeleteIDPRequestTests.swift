import XCTest
@testable import TandemCore

final class DeleteIDPRequestTests: XCTestCase {
    func testDeleteIDPRequest_idpId2() {
        MessageTester.initPumpState("", 0)
        let expected = DeleteIDPRequest(idpId: 2)

        let parsed: DeleteIDPRequest = MessageTester.test(
            "014dae4d1a0201c0493e208cb42b3ffcb6f3f0a9",
            77,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "004de51d3ea637ac1b02df4cce79c8"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testDeleteIDPRequest_idpId1() {
        MessageTester.initPumpState("", 0)
        let expected = DeleteIDPRequest(idpId: 1)

        let parsed: DeleteIDPRequest = MessageTester.test(
            "0153ae531a0101cf493e200e7a1458b74d619de6",
            83,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "0053faa1644c35799cdc81ac28666a"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
