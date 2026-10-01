@testable import TandemKit
import XCTest

final class SetIDPSegmentResponseTests: XCTestCase {
    func testSetIDPSegmentResponse() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetIDPSegmentResponse(cargo: Data([0x00, 0x02]))

        let parsed: SetIDPSegmentResponse = MessageTester.test(
            "002dab2d1a000260033e205bc7dccaad0b38c91c4f40c451c67c31f90c26c1ccb4",
            45,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
