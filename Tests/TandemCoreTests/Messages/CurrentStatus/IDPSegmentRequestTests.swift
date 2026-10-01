@testable import TandemKit
import XCTest

final class IDPSegmentRequestTests: XCTestCase {
    func testIDPSegmentRequest() {
        let expected = IDPSegmentRequest(idpId: 0, segmentIndex: 0)

        let parsed: IDPSegmentRequest = MessageTester.test(
            "0004420402000076e0",
            4,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.idpId)
        XCTAssertEqual(0, parsed.segmentIndex)
    }
}
