@testable import TandemKit
import XCTest

final class MalfunctionBitmaskStatusResponseTests: XCTestCase {
    func testMalfunctionBitmaskStatusResponse_zeroBitmaskFixture() {
        let expected = MalfunctionBitmaskStatusResponse(bitmask: 0)

        let parsed = MalfunctionBitmaskStatusResponse(cargo: Data(hexadecimalString: "0000000000000000")!)

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.bitmask)
        XCTAssertTrue(parsed.malfunctions.isEmpty)
        XCTAssertEqual(0, parsed.notificationCount)
    }
}
