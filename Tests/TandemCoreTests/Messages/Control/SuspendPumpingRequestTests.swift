@testable import TandemKit
import XCTest

final class SuspendPumpingRequestTests: XCTestCase {
    func testSuspendPumpingRequest() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SuspendPumpingRequest()

        let parsed: SuspendPumpingRequest = MessageTester.test(
            "01659c651838eaee1f67bfcaf05f7c5e09412c65",
            101,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00651de503c71694d7e46bce00"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
