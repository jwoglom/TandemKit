@testable import TandemKit
import XCTest

final class PlaySoundResponseTests: XCTestCase {
    func testPlaySoundResponse() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = PlaySoundResponse(cargo: Data([0x00]))

        let parsed: PlaySoundResponse = MessageTester.test(
            "00cef5ce1900cef0f21fbf00d7c6462ba60db8d201b730849ce4458962818856",
            -50,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
