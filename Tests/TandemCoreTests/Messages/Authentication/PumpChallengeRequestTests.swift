@testable import TandemCore
import XCTest

final class PumpChallengeRequestTests: XCTestCase {
    func testTconnectAppPumpChallengeRequest() {
        MessageTester.initPumpState("test", 0)
        let pumpChallengeHash = Data(hexadecimalString: "0194a8f98ca49cddf70c2c1331730290bca3df07")!
        let expected = PumpChallengeRequest(appInstanceId: 1, pumpChallengeHash: pumpChallengeHash)

        let parsed: PumpChallengeRequest = MessageTester.test(
            "010112011601000194a8f98ca49cddf70c2c1331",
            1,
            2,
            .AUTHORIZATION_CHARACTERISTICS,
            expected,
            "0001730290bca3df079967"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(expected.appInstanceId, parsed.appInstanceId)
        MessageTester.assertHexEquals(expected.pumpChallengeHash, parsed.pumpChallengeHash)
    }
}
