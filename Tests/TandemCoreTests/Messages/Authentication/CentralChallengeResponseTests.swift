@testable import TandemCore
import XCTest

final class CentralChallengeResponseTests: XCTestCase {
    func testTconnectAppFirstPumpReplyMessage_legacyAuth() {
        MessageTester.initPumpState("test", 0)
        let centralChallengeHash = Data(hexadecimalString: "8c212d7a8fbda85f83a3440254488dfb561264ec")!
        let hmacKey = Data(hexadecimalString: "840c4e16873046bc")!
        let expected = CentralChallengeResponse(appInstanceId: 1, centralChallengeHash: centralChallengeHash, hmacKey: hmacKey)

        let parsed: CentralChallengeResponse = MessageTester.test(
            "000011001e01008c212d7a8fbda85f83a3440254488dfb561264ec840c4e16873046bc2c1a",
            0,
            2,
            .AUTHORIZATION_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(expected.appInstanceId, parsed.appInstanceId)
        MessageTester.assertHexEquals(expected.centralChallengeHash, parsed.centralChallengeHash)
        MessageTester.assertHexEquals(expected.hmacKey, parsed.hmacKey)
    }
}
