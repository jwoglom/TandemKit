import XCTest
@testable import TandemCore

final class PumpChallengeResponseTests: XCTestCase {
    func testTconnectAppChallengeResponseMessageSuccess_legacyAuth() {
        MessageTester.initPumpState("test", 0)
        let expected = PumpChallengeResponse(appInstanceId: 1, success: true)

        let parsed: PumpChallengeResponse = MessageTester.test(
            "0001130103010001e8cc",
            1,
            1,
            .AUTHORIZATION_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(expected.appInstanceId, parsed.appInstanceId)
        XCTAssertEqual(expected.success, parsed.success)
    }

    func testTconnectAppChallengeResponseMessageFailure_legacyAuth() {
        MessageTester.initPumpState("test", 0)
        let expected = PumpChallengeResponse(appInstanceId: 1, success: false)

        let parsed: PumpChallengeResponse = MessageTester.test(
            "0001130103010000c9dc",
            1,
            1,
            .AUTHORIZATION_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(expected.appInstanceId, parsed.appInstanceId)
        XCTAssertEqual(expected.success, parsed.success)
    }
}
