import XCTest
@testable import TandemCore

final class Jpake3SessionKeyRequestTests: XCTestCase {
    func test167cargoFourthchallengeSplit() {
        MessageTester.initPumpState("test", 0)
        let expected = Jpake3SessionKeyRequest(challengeParam: 0)

        let parsed: Jpake3SessionKeyRequest = MessageTester.test(
            "000326030200008121",
            3,
            1,
            .AUTHORIZATION_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.challengeParam)
    }
}
