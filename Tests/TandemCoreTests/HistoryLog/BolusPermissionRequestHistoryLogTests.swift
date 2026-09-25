@testable import TandemKit
import XCTest

final class BolusPermissionRequestHistoryLogTests: XCTestCase {
    func testMobiTandemKitRequest() {
        let expected = BolusPermissionRequestHistoryLog(
            pumpTimeSec: 589529230, sequenceNum: 640842, requestTimestamp: 195084
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle("52118e8023234ac709000cfa0200000000000000000000000000", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.requestTimestamp, 195084)
    }

    func testX2OfficialAppRequest() {
        let expected = BolusPermissionRequestHistoryLog(
            pumpTimeSec: 461464522, sequenceNum: 23532, requestTimestamp: 461464512
        )

        let parsed = HistoryLogMessageTester.testSingle("5201ca63811bec5b0000c063811b000000000000000000000000", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.requestTimestamp, 461464512)
    }
}
