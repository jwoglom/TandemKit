@testable import TandemKit
import XCTest

final class SetPumpSoundsResponseTests: XCTestCase {
    func testSetPumpSoundsResponse() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetPumpSoundsResponse(status: 0)

        let parsed: SetPumpSoundsResponse = MessageTester.test(
            "004ee54e1900648168208bb1895bc466198b6c049eb08f073d9afed28dba8c00",
            78,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
    }
}
