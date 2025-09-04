import XCTest
@testable import TandemCore

final class ExitChangeCartridgeModeRequestTests: XCTestCase {
    func testExitChangeCartridgeModeRequest() {
        MessageTester.initPumpState("", 0)
        let expected = ExitChangeCartridgeModeRequest()
        let parsed: ExitChangeCartridgeModeRequest = MessageTester.test(
            "0189928918e40e4120bd5bce64b42a9df62d8cae",
            -119,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "0089e8d1e8325cc6cacddc7790"
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
