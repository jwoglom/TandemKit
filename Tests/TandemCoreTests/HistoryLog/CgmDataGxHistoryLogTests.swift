@testable import TandemKit
import XCTest

final class CgmDataGxHistoryLogTests: XCTestCase {
    func testCgmDataGxHistoryLogBuildCargoRoundTrip() {
        let log = CgmDataGxHistoryLog(
            pumpTimeSec: 446_191_545,
            sequenceNum: 187_445,
            status: 0,
            type: 1,
            rate: -2,
            rssi: -89,
            value: 112,
            timestamp: 446_191_545,
            transmitterTimestamp: 446_191_540
        )

        XCTAssertEqual(log.cargo.count, 26)
        XCTAssertEqual(log.cargo[14], 0)
        let parsed = HistoryLogParser.parse(log.cargo) as? CgmDataGxHistoryLog
        XCTAssertNotNil(parsed)
        MessageTester.assertHexEquals(log.cargo, parsed?.cargo ?? Data())
        XCTAssertEqual(parsed?.status, 0)
        XCTAssertEqual(parsed?.type, 1)
        XCTAssertEqual(parsed?.rate, -2)
        XCTAssertEqual(parsed?.rssi, -89)
        XCTAssertEqual(parsed?.value, 112)
        XCTAssertEqual(parsed?.timestamp, 446_191_545)
        XCTAssertEqual(parsed?.transmitterTimestamp, 446_191_540)
    }
}
