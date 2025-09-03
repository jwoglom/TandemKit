import XCTest
@testable import TandemCore

final class EnterFillTubingModeRequestTests: XCTestCase {
    func testEnterFillTubingModeRequest() {
        MessageTester.initPumpState("", 0)
        let expected = EnterFillTubingModeRequest()
        let parsed: EnterFillTubingModeRequest = MessageTester.test(
            "017a947a1851eaee1f5595738c382cc5dc5552a2",
            122,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "007a4aa8482c322b5fd69805e8"
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
