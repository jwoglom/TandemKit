import XCTest
@testable import TandemCore

final class DisconnectPumpRequestTests: XCTestCase {
    func testDisconnectPumpRequest() {
        MessageTester.initPumpState("", 0)
        let expected = DisconnectPumpRequest()
        let parsed: DisconnectPumpRequest = MessageTester.test(
            "01debede18da38f31f38413194c36c036e110c25",
            -34,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00deff81b3f10f7af28dcfb8fc"
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
