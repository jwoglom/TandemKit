@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `SyncDoseStartHistoryLogTest`.
final class SyncDoseStartHistoryLogTests: XCTestCase {
    func testSyncDoseStartHistoryLogParse() {
        let expected = SyncDoseStartHistoryLog(
            pumpTimeSec: 566_516_808,
            sequenceNum: 506_706,
            doseId: 300,
            doseSource: 2,
            tempAdjustmentPercent: 3,
            syncDoseSizeRequested: 2.75,
            currentBasalRate: 304,
            profileBasalRate: 305,
            activeInsulin: 4.25
        )

        let parsed = HistoryLogParser.parse(expected.cargo)
        guard let parsedRes = parsed as? SyncDoseStartHistoryLog else {
            XCTFail("parsed \(type(of: parsed)), expected SyncDoseStartHistoryLog")
            return
        }

        XCTAssertEqual(expected.pumpTimeSec, parsedRes.pumpTimeSec)
        XCTAssertEqual(expected.sequenceNum, parsedRes.sequenceNum)
        XCTAssertEqual(expected.doseId, parsedRes.doseId)
        XCTAssertEqual(expected.doseSource, parsedRes.doseSource)
        XCTAssertEqual(expected.tempAdjustmentPercent, parsedRes.tempAdjustmentPercent)
        XCTAssertEqual(expected.syncDoseSizeRequested, parsedRes.syncDoseSizeRequested)
        XCTAssertEqual(expected.currentBasalRate, parsedRes.currentBasalRate)
        XCTAssertEqual(expected.profileBasalRate, parsedRes.profileBasalRate)
        XCTAssertEqual(expected.activeInsulin, parsedRes.activeInsulin)
    }
}
