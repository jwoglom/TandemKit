@testable import TandemKit
import XCTest

final class CgmDataFsl2HistoryLogTests: XCTestCase {
    func testCgmDataFsl2HistoryLogParse() {
        let expected = CgmDataFsl2HistoryLog(
            pumpTimeSec: 566516808,
            sequenceNum: 506706,
            status: 3,
            type: 1,
            rate: 4,
            rssi: -61,
            value: 257,
            timestamp: 566516805,
            transmitterTimestamp: 566512000
        )

        let parsed = HistoryLogParser.parse(expected.cargo)
        guard let parsedRes = parsed as? CgmDataFsl2HistoryLog else {
            XCTFail("parsed \(type(of: parsed)), expected CgmDataFsl2HistoryLog")
            return
        }

        XCTAssertEqual(expected.pumpTimeSec, parsedRes.pumpTimeSec)
        XCTAssertEqual(expected.sequenceNum, parsedRes.sequenceNum)
        XCTAssertEqual(expected.status, parsedRes.status)
        XCTAssertEqual(expected.type, parsedRes.type)
        XCTAssertEqual(expected.rate, parsedRes.rate)
        XCTAssertEqual(expected.rssi, parsedRes.rssi)
        XCTAssertEqual(expected.value, parsedRes.value)
        XCTAssertEqual(expected.timestamp, parsedRes.timestamp)
        XCTAssertEqual(expected.transmitterTimestamp, parsedRes.transmitterTimestamp)
    }
}
