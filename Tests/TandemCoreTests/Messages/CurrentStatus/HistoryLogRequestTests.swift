@testable import TandemKit
import XCTest

final class HistoryLogRequestTests: XCTestCase {
    func testHistoryLogRequest10Messages() {
        let expected = HistoryLogRequest(startLog: 3950, numberOfLogs: 10)

        let parsed: HistoryLogRequest = MessageTester.test(
            "00043c04056e0f00000a4247",
            4,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(3950, parsed.startLog)
        XCTAssertEqual(10, parsed.numberOfLogs)
    }
}
