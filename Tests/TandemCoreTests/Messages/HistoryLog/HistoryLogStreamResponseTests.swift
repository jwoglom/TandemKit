import Foundation
@testable import TandemCore
import XCTest

final class HistoryLogStreamResponseTests: XCTestCase {
    func testHasExpectedLengthTrueWhenCountMatchesPayload() {
        let log = BolusActivatedHistoryLog(pumpTimeSec: 100, sequenceNum: 5, bolusId: 7, iob: 0, bolusSize: 1.25)
        let response = HistoryLogStreamResponse(numberOfHistoryLogs: 1, streamId: 9, historyLogStreamBytes: [log.cargo])

        XCTAssertTrue(response.hasExpectedLength)
    }

    func testHasExpectedLengthFalseWhenCountDoesNotMatchPayload() {
        let log = BolusActivatedHistoryLog(pumpTimeSec: 100, sequenceNum: 5, bolusId: 7, iob: 0, bolusSize: 1.25)
        let cargo = Data([2, 9]) + log.cargo // declares 2 logs, includes 1
        let response = HistoryLogStreamResponse(cargo: cargo)

        XCTAssertFalse(response.hasExpectedLength)
        XCTAssertEqual(response.numberOfHistoryLogs, 2)
        XCTAssertTrue(response.historyLogStreamBytes.isEmpty)
        XCTAssertTrue(response.historyLogs.isEmpty)
    }
}
