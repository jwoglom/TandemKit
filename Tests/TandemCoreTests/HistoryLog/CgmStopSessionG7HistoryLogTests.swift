@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `CgmStopSessionG7HistoryLogTest`.
final class CgmStopSessionG7HistoryLogTests: XCTestCase {
    func testCgmStopSessionG7HistoryLogParse() {
        // pumpTimeSec, sequenceNum, currentTransmitterTime, sessionStartTime, sessionStopTime, stopSessionCode, sessionStopReason, sessionDuration
        let expected = CgmStopSessionG7HistoryLog(
            pumpTimeSec: 566_516_808,
            sequenceNum: 506_706,
            currentTransmitterTime: 566_516_805,
            sessionStartTime: 566_430_000,
            sessionStopTime: 566_516_800,
            stopSessionCode: 1,
            sessionStopReason: 2,
            sessionDuration: 10
        )

        let rawHex = "bf01485cc42152bb0700455cc4213009c321405cc4210a020100"
        XCTAssertEqual(rawHex, expected.cargo.hexadecimalString)

        let parsed = HistoryLogMessageTester.testSingle(rawHex, expected)

        XCTAssertEqual(expected.pumpTimeSec, parsed.pumpTimeSec)
        XCTAssertEqual(expected.sequenceNum, parsed.sequenceNum)
        XCTAssertEqual(expected.currentTransmitterTime, parsed.currentTransmitterTime)
        XCTAssertEqual(expected.sessionStartTime, parsed.sessionStartTime)
        XCTAssertEqual(expected.sessionStopTime, parsed.sessionStopTime)
        XCTAssertEqual(expected.stopSessionCode, parsed.stopSessionCode)
        XCTAssertEqual(expected.sessionStopReason, parsed.sessionStopReason)
        XCTAssertEqual(expected.sessionDuration, parsed.sessionDuration)
    }

    // Tandem Mobi + Dexcom G7, official app BLE capture: written when a new sensor code was entered after
    // StopDexcomCGMSensorSessionRequest; 905914 s is inside the 12 h grace period after the 10-day session.
    func testCgmStopSessionG7HistoryLogUserStopMobi() {
        let expected = CgmStopSessionG7HistoryLog(
            pumpTimeSec: 542_807_916,
            sequenceNum: 231_564,
            currentTransmitterTime: 905_914,
            sessionStartTime: 91,
            sessionStopTime: 0,
            stopSessionCode: 0,
            sessionStopReason: 16,
            sessionDuration: 10
        ).withHeaderHighNibble(1)

        let parsed: CgmStopSessionG7HistoryLog = HistoryLogMessageTester.testSingle(
            "bf116c975a208c880300bad20d005b000000000000000a100000",
            expected
        )
        XCTAssertEqual(905_914, parsed.currentTransmitterTime)
        XCTAssertEqual(91, parsed.sessionStartTime)
        XCTAssertEqual(10, parsed.sessionDuration)
        XCTAssertEqual(16, parsed.sessionStopReason)
        XCTAssertEqual(0, parsed.stopSessionCode)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    // t:slim X2 + Dexcom G7, official app BLE capture: no stop request preceded it, and 907415 s is past the
    // 10-day session plus 12 h grace (907200 s).
    func testCgmStopSessionG7HistoryLogExpiredX2() {
        let expected = CgmStopSessionG7HistoryLog(
            pumpTimeSec: 534_413_823,
            sequenceNum: 1_061_554,
            currentTransmitterTime: 907_415,
            sessionStartTime: 4_294_967_295,
            sessionStopTime: 0,
            stopSessionCode: 0,
            sessionStopReason: 14,
            sessionDuration: 10
        )

        let parsed: CgmStopSessionG7HistoryLog = HistoryLogMessageTester.testSingle(
            "bf01ff81da1fb232100097d80d00ffffffff000000000a0e0000",
            expected
        )
        XCTAssertEqual(907_415, parsed.currentTransmitterTime)
        XCTAssertEqual(10, parsed.sessionDuration)
        XCTAssertEqual(14, parsed.sessionStopReason)
        XCTAssertEqual(0, parsed.stopSessionCode)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
