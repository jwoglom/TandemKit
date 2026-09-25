@testable import TandemKit
import XCTest

final class InitiateBolusRequestMsg3HistoryLogTests: XCTestCase {
    func testMobiTandemKitBolus() {
        let expected = InitiateBolusRequestMsg3HistoryLog(
            pumpTimeSec: 589529231, sequenceNum: 640851, transactionId: 139, bolusId: 2904, bolusIOB: 0, extendedSeconds: 0, extended3: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle("57118f80232353c709008b00580b000000000000000000000000", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.transactionId, 139)
    }

    // The captured InitiateBolusRequest: txId 57, bolusIOB 130.
    func testX2OfficialAppBolusIob() {
        let expected = InitiateBolusRequestMsg3HistoryLog(
            pumpTimeSec: 461589433, sequenceNum: 25684, transactionId: 57, bolusId: 10653, bolusIOB: 130, extendedSeconds: 0, extended3: 0
        )

        let parsed = HistoryLogMessageTester.testSingle("5701b94b831b5464000039009d29820000000000000000000000", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.bolusIOB, 130)
    }

    // Synthetic: no maintainer capture holds an extended BLE bolus.
    func testSyntheticExtendedSecondsRoundTrips() {
        let built = InitiateBolusRequestMsg3HistoryLog(
            pumpTimeSec: 1, sequenceNum: 2, transactionId: 32, bolusId: 248, bolusIOB: 0, extendedSeconds: 28800, extended3: 0
        )
        let parsed = HistoryLogParser.parse(built.cargo) as? InitiateBolusRequestMsg3HistoryLog
        XCTAssertEqual(parsed?.extendedSeconds, 28800)
    }
}
