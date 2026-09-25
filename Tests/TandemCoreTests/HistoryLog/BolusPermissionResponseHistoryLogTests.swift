@testable import TandemKit
import XCTest

final class BolusPermissionResponseHistoryLogTests: XCTestCase {
    func testMobiPermissionGranted() {
        let expected = BolusPermissionResponseHistoryLog(
            pumpTimeSec: 589529230, sequenceNum: 640843, bolusId: 2904, unknownU8At14: 0, unknownU8At15: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle("29118e8023234bc70900580b0000000000000000000000000000", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.bolusId, 2904)
    }

    func testX2PermissionRefused() {
        let expected = BolusPermissionResponseHistoryLog(
            pumpTimeSec: 461464522, sequenceNum: 23533, bolusId: 0, unknownU8At14: 1, unknownU8At15: 1
        )

        let parsed = HistoryLogMessageTester.testSingle("2901ca63811bed5b000000000000010100000000000000000000", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.bolusId, 0)
        XCTAssertEqual(parsed.unknownU8At14, 1)
        XCTAssertEqual(parsed.unknownU8At15, 1)
    }
}
