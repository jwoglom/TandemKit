@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `SyncDoseCompleteHistoryLogTest`.
final class SyncDoseCompleteHistoryLogTests: XCTestCase {
    func testSyncDoseCompleteHistoryLogParse() {
        let expected = SyncDoseCompleteHistoryLog(
            pumpTimeSec: 566_516_808,
            sequenceNum: 506_706,
            doseId: 300,
            doseSource: 2,
            tempAdjustmentPercent: 3,
            syncDoseSizeDelivered: 2.75,
            currentBasalRate: 304,
            activeInsulin: 3.75
        )

        let parsed = HistoryLogParser.parse(expected.cargo)
        guard let parsedRes = parsed as? SyncDoseCompleteHistoryLog else {
            XCTFail("parsed \(type(of: parsed)), expected SyncDoseCompleteHistoryLog")
            return
        }

        XCTAssertEqual(expected.pumpTimeSec, parsedRes.pumpTimeSec)
        XCTAssertEqual(expected.sequenceNum, parsedRes.sequenceNum)
        XCTAssertEqual(expected.doseId, parsedRes.doseId)
        XCTAssertEqual(expected.doseSource, parsedRes.doseSource)
        XCTAssertEqual(expected.tempAdjustmentPercent, parsedRes.tempAdjustmentPercent)
        XCTAssertEqual(expected.syncDoseSizeDelivered, parsedRes.syncDoseSizeDelivered)
        XCTAssertEqual(expected.currentBasalRate, parsedRes.currentBasalRate)
        XCTAssertEqual(expected.activeInsulin, parsedRes.activeInsulin)
    }
}
