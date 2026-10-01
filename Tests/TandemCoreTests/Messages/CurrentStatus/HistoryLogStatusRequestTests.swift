@testable import TandemKit
import XCTest

final class HistoryLogStatusRequestTests: XCTestCase {
    func testHistoryLogStatusRequest() {
        let expected = HistoryLogStatusRequest()

        let parsed: HistoryLogStatusRequest = MessageTester.test(
            "00033a0300ab9b",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
