@testable import TandemKit
import XCTest

final class HistoryLogStatusResponseTests: XCTestCase {
    func testHistoryLogStatusResponse() {
        let expected = HistoryLogStatusResponse(numEntries: 2756, firstSequenceNum: 0, lastSequenceNum: 2755)

        let parsed: HistoryLogStatusResponse = MessageTester.test(
            "00033b030cc40a000000000000c30a0000d84d",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(2756, parsed.numEntries)
        XCTAssertEqual(0, parsed.firstSequenceNum)
        XCTAssertEqual(2755, parsed.lastSequenceNum)
    }
}
