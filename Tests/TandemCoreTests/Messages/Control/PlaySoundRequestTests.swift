import XCTest
@testable import TandemCore

final class PlaySoundRequestTests: XCTestCase {
    func testPlaySoundRequest() {
        MessageTester.initPumpState("", 0)
        let expected = PlaySoundRequest()

        let parsed: PlaySoundRequest = MessageTester.test(
            "01cef4ce182337f31f36da5eea5ed250773df9b0",
            -50,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00ce91daca790983cb56d5fff1"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
