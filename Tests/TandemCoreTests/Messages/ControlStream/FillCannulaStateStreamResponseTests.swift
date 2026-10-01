@testable import TandemKit
import XCTest

final class FillCannulaStateStreamResponseTests: XCTestCase {
    func testFillCannulaStateStreamResponse_complete() {
        let expected = FillCannulaStateStreamResponse(stateId: 2)

        let parsed: FillCannulaStateStreamResponse = MessageTester.test(
            "0070e7701902e7d64020c63c1d5e2cfb1fecb965df1f825d770093d1d6461306",
            112,
            1,
            .CONTROL_STREAM_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(2, parsed.stateId)
        XCTAssertEqual(.cannulaFilled, parsed.state)
    }
}
