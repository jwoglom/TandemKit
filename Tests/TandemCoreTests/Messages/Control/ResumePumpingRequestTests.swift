import XCTest
@testable import TandemCore

final class ResumePumpingRequestTests: XCTestCase {
    func testResumePumpingRequest() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = ResumePumpingRequest()

        let parsed: ResumePumpingRequest = MessageTester.test(
            "013d9a3d1808eaee1ff9e90b186d391c9892ca8f",
            61,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "003d7bc20e2a68cc7bc5c6fcce"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
