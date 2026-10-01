@testable import TandemKit
import XCTest

final class ShelfModeHistoryLogTests: XCTestCase {
    func testShelfModeHistoryLog1() {
        // pumpTimeSec, sequenceNum, msecSinceReset, lipoIbc, lipoAbc, lipoCurrent, lipoRemCap, lipoMv
        let expected = ShelfModeHistoryLog(
            pumpTimeSec: 580_777_764,
            sequenceNum: 491_136,
            msecSinceReset: 1_078_644_679,
            lipoIbc: 90,
            lipoAbc: 90,
            lipoCurrent: 0,
            lipoRemCap: 130,
            lipoMv: 4176
        ).withHeaderHighNibble(1)

        let parsedRes = HistoryLogMessageTester.testSingle(
            "351024f79d22807e0700c7cf4a4000005a5a8200000050100000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
        XCTAssertEqual(0, parsedRes.lipoCurrent)
        XCTAssertEqual(90, parsedRes.lipoAbc)
        XCTAssertEqual(90, parsedRes.lipoIbc)
    }
}
