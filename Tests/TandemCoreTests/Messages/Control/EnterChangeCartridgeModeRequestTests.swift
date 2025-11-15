@testable import TandemCore
import XCTest

final class EnterChangeCartridgeModeRequestTests: XCTestCase {
    func testEnterChangeCartridgeModeRequest() {
        MessageTester.initPumpState("", 0)
        let expected = EnterChangeCartridgeModeRequest()
        let parsed: EnterChangeCartridgeModeRequest = MessageTester.test(
            "01369036181d142820db51e5fa626a7df87fc2cf",
            54,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "003621097bdd2395333e5d7d63"
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
