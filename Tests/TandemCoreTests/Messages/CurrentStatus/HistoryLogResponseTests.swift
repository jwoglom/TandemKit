@testable import TandemKit
import XCTest

final class HistoryLogResponseTests: XCTestCase {
    func testHistoryLogResponse() {
        let expected = HistoryLogResponse(status: 0, streamId: 1)

        let parsed: HistoryLogResponse = MessageTester.test(
            "00033d0302000105d9",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
        XCTAssertEqual(1, parsed.streamId)
    }
}
