@testable import TandemCore
import XCTest

final class BolusPermissionReleaseResponseTests: XCTestCase {
    func testBolusPermissionReleaseResponse_ID10676() {
        MessageTester.initPumpState("6VeDeRAL5DCigGw2", 461_710_079)

        let expected = BolusPermissionReleaseResponse(status: 0)

        let parsed: BolusPermissionReleaseResponse = MessageTester.test(
            "003af13a19003923851b8854859ea0fc17fe530b3c3c4208ae30a555356f0985",
            58,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(.success, parsed.releaseStatus)
    }

    func testBolusPermissionReleaseResponse_ID10737_initial() {
        MessageTester.initPumpState("Ns7vSuFYcfTLAXmb", 461_710_079)

        let expected = BolusPermissionReleaseResponse(status: 0)

        let parsed: BolusPermissionReleaseResponse = MessageTester.test(
            "0005f105190099abe11b341684fe037937a533833292ee3df0d4bc008b71fca4",
            5,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(.success, parsed.releaseStatus)
    }

    func testBolusPermissionReleaseResponse_ID10737_second_time() {
        MessageTester.initPumpState("Ns7vSuFYcfTLAXmb", 461_710_079)

        let expected = BolusPermissionReleaseResponse(status: 1)

        let parsed: BolusPermissionReleaseResponse = MessageTester.test(
            "0006f1061901a2abe11b6fbc54b70597cb6d423d18d162cd350efcfcb9f5a16a",
            6,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(.failure, parsed.releaseStatus)
    }
}
