@testable import TandemCore
import XCTest

final class CentralChallengeRequestTests: XCTestCase {
    func testTconnectAppFirstRequest() {
        MessageTester.initPumpState("test", 0)
        let centralChallengeHex = "4d08435da2694735"
        let expected = CentralChallengeRequest(appInstanceId: 0, centralChallenge: Data(hexadecimalString: centralChallengeHex)!)

        let parsed: CentralChallengeRequest = MessageTester.test(
            "000010000a00004d08435da26947356d6f",
            0,
            1,
            .AUTHORIZATION_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(expected.appInstanceId, parsed.appInstanceId)
        MessageTester.assertHexEquals(expected.centralChallenge, parsed.centralChallenge)
    }
}
