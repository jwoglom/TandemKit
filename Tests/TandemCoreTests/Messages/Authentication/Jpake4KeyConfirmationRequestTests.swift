@testable import TandemCore
import XCTest

final class Jpake4KeyConfirmationRequestTests: XCTestCase {
    func test167cargoFifthchallengeSplit() {
        MessageTester.initPumpState("test", 0)
        let nonce = Data(hexadecimalString: "571ad034741c777d")!
        let reserved = Data(hexadecimalString: "0000000000000000")!
        let hashDigest = Data(hexadecimalString: "2fece0828a91f7372a47cb7bf597a296961f66f0f45c4b7b76e9aeaf8f176f6d")!
        let expected = Jpake4KeyConfirmationRequest(appInstanceId: 0, nonce: nonce, reserved: reserved, hashDigest: hashDigest)

        let parsed: Jpake4KeyConfirmationRequest = MessageTester.test(
            "03042804320000571ad034741c777d0000000000",
            4,
            4,
            .AUTHORIZATION_CHARACTERISTICS,
            expected,
            "02040000002fece0828a91f7372a47cb7bf597a2",
            "010496961f66f0f45c4b7b76e9aeaf8f176f6d44",
            "00046e"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.appInstanceId)
        MessageTester.assertHexEquals(expected.hashDigest, parsed.hashDigest)
        MessageTester.assertHexEquals(expected.reserved, parsed.reserved)
        MessageTester.assertHexEquals(expected.nonce, parsed.nonce)
    }
}
