@testable import TandemKit
import XCTest

final class ArmInitHistoryLogTests: XCTestCase {
    func testArmInitHistoryLogFromAMobiWokenFromShelfMode() {
        let expected = ArmInitHistoryLog(
            pumpTimeSec: 212,
            sequenceNum: 2_973_278,
            version: 3_553_172_181,
            configABits: 0,
            configBBits: 0,
            numLogEntries: 0
        ).withHeaderHighNibble(1)

        let parsedRes = HistoryLogMessageTester.testSingle(
            "6310d40000005e5e2d00d51ac9d3000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
        XCTAssertEqual(212, parsedRes.pumpTimeSec)
        XCTAssertEqual(3_553_172_181, parsedRes.version)
    }
}
