@testable import TandemKit
import XCTest

final class DexcomG6CGMHistoryLogTests: XCTestCase {
    func testDexcomG6CGMHistoryLog1() {
        let expected = DexcomG6CGMHistoryLog(
            pumpTimeSec: 446_191_545,
            sequenceNum: 187_445,
            glucoseValueStatus: 0,
            cgmDataType: 1,
            rate: -2,
            algorithmState: 6,
            rssi: -89,
            currentGlucoseDisplayValue: 112,
            timeStampSeconds: 446_191_545,
            egvInfoBitmask: 481,
            interval: 0
        )

        let parsedRes = HistoryLogMessageTester.testSingle(
            "0001b957981a35dc0200000001fe06a77000b957981ae1010001",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
        XCTAssertEqual(parsedRes.rate, -2)
        XCTAssertEqual(parsedRes.rssi, -89)
        XCTAssertEqual(parsedRes.glucoseValueStatusEnum, .PRECISE_VALUE)
        XCTAssertEqual(parsedRes.cgmDataTypes, [.FIVE_MINUTE_READING])
        XCTAssertEqual(
            parsedRes.egvInfo,
            [.FIVE_MINUTE_READING, .VALID_TIMESTAMP, .VALID_EGV_RANGE, .VALID_ALG_STATE, .EGV_PROCESSED]
        )
        XCTAssertEqual(parsedRes.egvCount, 1)
        XCTAssertEqual(parsedRes.egvSensorType, .notApplicable)
    }

    func testDexcomG6CGMHistoryLog2() {
        let expected = DexcomG6CGMHistoryLog(
            pumpTimeSec: 446_115_345,
            sequenceNum: 184_926,
            glucoseValueStatus: 0,
            cgmDataType: 1,
            rate: -3,
            algorithmState: 6,
            rssi: -67,
            currentGlucoseDisplayValue: 81,
            timeStampSeconds: 446_115_345,
            egvInfoBitmask: 481,
            interval: 0
        )

        let parsedRes = HistoryLogMessageTester.testSingle(
            "0001112e971a5ed20200000001fd06bd5100112e971ae1010001",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
        XCTAssertEqual(parsedRes.rate, -3)
        XCTAssertEqual(parsedRes.rssi, -67)
    }

    func testDexcomG6CGMHistoryLog3() {
        let expected = DexcomG6CGMHistoryLog(
            pumpTimeSec: 446_090_145,
            sequenceNum: 184_327,
            glucoseValueStatus: 0,
            cgmDataType: 1,
            rate: -12,
            algorithmState: 6,
            rssi: -82,
            currentGlucoseDisplayValue: 78,
            timeStampSeconds: 446_090_145,
            egvInfoBitmask: 481,
            interval: 0
        )

        let parsedRes = HistoryLogMessageTester.testSingle(
            "0001a1cb961a07d00200000001f406ae4e00a1cb961ae1010001",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
        XCTAssertEqual(parsedRes.rate, -12)
        XCTAssertEqual(parsedRes.rssi, -82)
    }

    func testDexcomG6CGMHistoryLog4() {
        let expected = DexcomG6CGMHistoryLog(
            pumpTimeSec: 445_997_146,
            sequenceNum: 181_873,
            glucoseValueStatus: 0,
            cgmDataType: 1,
            rate: 13,
            algorithmState: 6,
            rssi: -87,
            currentGlucoseDisplayValue: 145,
            timeStampSeconds: 445_997_146,
            egvInfoBitmask: 481,
            interval: 0
        )

        let parsedRes = HistoryLogMessageTester.testSingle(
            "00015a60951a71c602000000010d06a991005a60951ae1010001",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
        XCTAssertEqual(parsedRes.rate, 13)
        XCTAssertEqual(parsedRes.rssi, -87)
    }

    func testDexcomG6CGMHistoryLogSensorTypeBitsInEgvInfo() {
        let expected = DexcomG6CGMHistoryLog(
            pumpTimeSec: 497_795_797,
            sequenceNum: 1_905_958,
            glucoseValueStatus: 0,
            cgmDataType: 1,
            rate: -6,
            algorithmState: 6,
            rssi: -65,
            currentGlucoseDisplayValue: 155,
            timeStampSeconds: 497_795_797,
            egvInfoBitmask: 0x09E1,
            interval: 0
        )

        let parsedRes = HistoryLogMessageTester.testSingle(
            "0001d5c2ab1d26151d00000001fa06bf9b00d5c2ab1de1090001",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
        XCTAssertEqual(parsedRes.rate, -6)
        XCTAssertEqual(parsedRes.rssi, -65)
        XCTAssertEqual(
            parsedRes.egvInfo,
            [.FIVE_MINUTE_READING, .VALID_TIMESTAMP, .VALID_EGV_RANGE, .VALID_ALG_STATE, .EGV_PROCESSED]
        )
        XCTAssertEqual(parsedRes.egvSensorType, .dexcomG6)
    }

    func testDexcomG6CGMHistoryLogBackfill() {
        let expected = DexcomG6CGMHistoryLog(
            pumpTimeSec: 470_616_768,
            sequenceNum: 957_589,
            glucoseValueStatus: 0,
            cgmDataType: 2,
            rate: 0,
            algorithmState: 6,
            rssi: -66,
            currentGlucoseDisplayValue: 167,
            timeStampSeconds: 470_616_468,
            egvInfoBitmask: 2530,
            interval: 1,
            egvCount: 0
        )

        let parsedRes = HistoryLogMessageTester.testSingle(
            "0001c00a0d1c959c0e000000020006bea70094090d1ce2090100",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
        XCTAssertEqual(parsedRes.cgmDataTypes, [.BACKFILL])
        XCTAssertEqual(parsedRes.rssi, -66)
        XCTAssertEqual(parsedRes.interval, 1)
        XCTAssertEqual(parsedRes.egvCount, 0)
        XCTAssertEqual(parsedRes.egvSensorType, .dexcomG6)
    }

    func testDexcomG6CGMHistoryLogEgvCountRoundTrip() {
        let log = DexcomG6CGMHistoryLog(
            pumpTimeSec: 470_616_768,
            sequenceNum: 957_590,
            glucoseValueStatus: 0,
            cgmDataType: 1,
            rate: -3,
            algorithmState: 6,
            rssi: -70,
            currentGlucoseDisplayValue: 120,
            timeStampSeconds: 470_616_768,
            egvInfoBitmask: 0x09E1,
            interval: 0,
            egvCount: 2
        )

        XCTAssertEqual(log.cargo.count, 26)
        XCTAssertEqual(log.cargo[25], 2)
        let parsed = DexcomG6CGMHistoryLog(cargo: log.cargo)
        MessageTester.assertHexEquals(log.cargo, parsed.cargo)
        XCTAssertEqual(parsed.egvCount, 2)
        XCTAssertEqual(parsed.egvSensorType, .dexcomG6)
    }

    func testDexcomG6CGMHistoryLogNegativeValuesRoundTrip() {
        let log = DexcomG6CGMHistoryLog(
            pumpTimeSec: 1,
            sequenceNum: 2,
            glucoseValueStatus: 0,
            cgmDataType: 1,
            rate: -128,
            algorithmState: 6,
            rssi: -1,
            currentGlucoseDisplayValue: 100,
            timeStampSeconds: 1,
            egvInfoBitmask: 481,
            interval: 0
        )

        let parsed = DexcomG6CGMHistoryLog(cargo: log.cargo)
        XCTAssertEqual(parsed.rate, -128)
        XCTAssertEqual(parsed.rssi, -1)
    }
}
