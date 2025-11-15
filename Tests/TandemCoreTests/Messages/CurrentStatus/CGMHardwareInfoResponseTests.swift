import XCTest
@testable import TandemCore

final class CGMHardwareInfoResponseTests: XCTestCase {
    func testCGMHardwareInfoResponse() {
        let expected = CGMHardwareInfoResponse(hardwareInfoString: "8RR239", lastByte: 0)

        let parsed: CGMHardwareInfoResponse = MessageTester.test(
            "00036103113852523233390000000000000000000000a2a3",
            3,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(expected.hardwareInfoString, parsed.hardwareInfoString)
        XCTAssertEqual(expected.lastByte, parsed.lastByte)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
