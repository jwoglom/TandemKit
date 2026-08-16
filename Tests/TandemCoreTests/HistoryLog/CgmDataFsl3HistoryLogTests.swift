@testable import TandemKit
import XCTest

final class CgmDataFsl3HistoryLogTests: XCTestCase {
    func testCgmDataFsl3HistoryLogParse() {
        let expected = CgmDataFsl3HistoryLog(
            pumpTimeSec: 566516507,
            sequenceNum: 506696,
            status: 0,
            type: 1,
            rate: 13,
            rssi: -59,
            value: 261,
            timestamp: 566516504,
            transmitterTimestamp: 566510000
        )

        let parsed = HistoryLogParser.parse(expected.cargo)
        guard let parsedRes = parsed as? CgmDataFsl3HistoryLog else {
            XCTFail("parsed \(type(of: parsed)), expected CgmDataFsl3HistoryLog")
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
