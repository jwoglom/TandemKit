import XCTest
@testable import TandemCore

final class BolusPermissionReleaseRequestTests: XCTestCase {
    func testBolusPermissionReleaseRequest_ID10676() {
        MessageTester.initPumpState("6VeDeRAL5DCigGw2", 461710079)

        let expected = BolusPermissionReleaseRequest(bolusId: 10676)

        let parsed: BolusPermissionReleaseRequest = MessageTester.test(
            "013af03a1cb42900000023851b3c39b657fe391e",
            58,
            2,
            .CONTROL_CHARACTERISTICS,
            expected,
            "003ac14d83666a2599ae79a30e5d9b459a"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
