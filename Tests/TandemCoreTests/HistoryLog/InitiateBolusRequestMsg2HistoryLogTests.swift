@testable import TandemKit
import XCTest

final class InitiateBolusRequestMsg2HistoryLogTests: XCTestCase {
    func testMobiTandemKitBolus() {
        let expected = InitiateBolusRequestMsg2HistoryLog(
            pumpTimeSec: 589529231,
            sequenceNum: 640850,
            transactionId: 139,
            bolusId: 2904,
            correctionVolume: 0,
            extendedVolume: 0,
            bolusCarbs: 0,
            bolusBG: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle("25118f80232352c709008b00580b000000000000000000000000", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.transactionId, 139)
    }

    // The captured InitiateBolusRequest: txId 171, correctionVolume 720, bolusCarbs 5, bolusBG 185.
    func testX2OfficialAppFoodAndCorrectionBolus() {
        let expected = InitiateBolusRequestMsg2HistoryLog(
            pumpTimeSec: 461710176,
            sequenceNum: 28138,
            transactionId: 171,
            bolusId: 10677,
            correctionVolume: 720,
            extendedVolume: 0,
            bolusCarbs: 5,
            bolusBG: 185
        )

        let parsed = HistoryLogMessageTester.testSingle("25016023851bea6d0000ab00b529d0020000000000000500b900", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.correctionVolume, 720)
        XCTAssertEqual(parsed.bolusCarbs, 5)
        XCTAssertEqual(parsed.bolusBG, 185)
    }

    // Synthetic: no maintainer capture holds an extended BLE bolus.
    func testSyntheticExtendedVolumeRoundTrips() {
        let built = InitiateBolusRequestMsg2HistoryLog(
            pumpTimeSec: 1, sequenceNum: 2, transactionId: 32, bolusId: 248, correctionVolume: 0, extendedVolume: 2000, bolusCarbs: 0, bolusBG: 0
        )
        let parsed = HistoryLogParser.parse(built.cargo) as? InitiateBolusRequestMsg2HistoryLog
        XCTAssertEqual(parsed?.extendedVolume, 2000)
        XCTAssertEqual(parsed?.bolusId, 248)
    }
}
