import XCTest
@testable import TandemCore

final class SetActiveIDPRequestTests: XCTestCase {
    func testSetActiveIDPRequest_profileWithId1() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetActiveIDPRequest(idpId: 1)

        let parsed: SetActiveIDPRequest = MessageTester.test(
            "0119ec191a010165493e2009a33736acb3713492",
            25,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00199d7598653853bd78abd443ec3b"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testSetActiveIDPRequest_profileWithId0() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = SetActiveIDPRequest(idpId: 0)

        let parsed: SetActiveIDPRequest = MessageTester.test(
            "0124ec241a00017c493e2027b0811608d99b2431",
            36,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00249dec87124ebe4216766ea86133"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
