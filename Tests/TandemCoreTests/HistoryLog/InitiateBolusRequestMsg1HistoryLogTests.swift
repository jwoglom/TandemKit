@testable import TandemKit
import XCTest

final class InitiateBolusRequestMsg1HistoryLogTests: XCTestCase {
    func testMobiTandemKitBolus() {
        let expected = InitiateBolusRequestMsg1HistoryLog(
            pumpTimeSec: 589529231,
            sequenceNum: 640849,
            requestTimestamp: 195084,
            transactionId: 139,
            bolusTypeBitmask: 8,
            bolusId: 2904,
            totalVolume: 200,
            foodVolume: 200
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle("24118f80232351c709000cfa02008b08580bc8000000c8000000", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.transactionId, 139)
        XCTAssertEqual(parsed.bolusTypeBitmask, 8)
        XCTAssertEqual(parsed.bolusId, 2904)
        XCTAssertEqual(parsed.totalVolume, 200)
    }

    // The captured InitiateBolusRequest: txId 171, bolusTypeBitmask 3, totalVolume 770, foodVolume 50.
    func testX2OfficialAppFoodAndCorrectionBolus() {
        let expected = InitiateBolusRequestMsg1HistoryLog(
            pumpTimeSec: 461710176,
            sequenceNum: 28137,
            requestTimestamp: 461710145,
            transactionId: 171,
            bolusTypeBitmask: 3,
            bolusId: 10677,
            totalVolume: 770,
            foodVolume: 50
        )

        let parsed = HistoryLogMessageTester.testSingle("24016023851be96d00004123851bab03b5290203000032000000", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.totalVolume, 770)
        XCTAssertEqual(parsed.foodVolume, 50)
    }
}
