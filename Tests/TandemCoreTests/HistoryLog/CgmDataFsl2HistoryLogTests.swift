@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `CgmDataFsl2HistoryLogTest`. The fixture follows the Tandem Source event schema
/// layout for this record: status u8 @0, data type u8 @1, rate s16 @2, algorithm state u8 @4,
/// rssi s8 @5, value u16 @6, timestamp u32 @8, EGV info u16 @12, interval u8 @14.
final class CgmDataFsl2HistoryLogTests: XCTestCase {
    func testCgmDataFsl2HistoryLogParse() {
        let expected = CgmDataFsl2HistoryLog(
            pumpTimeSec: 566516808,
            sequenceNum: 506706,
            glucoseValueStatus: 1,
            cgmDataType: 32,
            rate: -2,
            algorithmState: 101,
            rssi: -59,
            currentGlucoseDisplayValue: 261,
            egvTimestamp: 566516504,
            egvInfoBitmask: 4577,
            interval: 1
        )

        let rawHex = "7401485cc42152bb07000120feff65c50501185bc421e1110100"
        XCTAssertEqual(rawHex, expected.cargo.hexadecimalString)

        let parsedRes = HistoryLogMessageTester.testSingle(rawHex, expected)
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)

        XCTAssertEqual(expected.pumpTimeSec, parsedRes.pumpTimeSec)
        XCTAssertEqual(expected.sequenceNum, parsedRes.sequenceNum)
        XCTAssertEqual(1, parsedRes.glucoseValueStatusRaw)
        XCTAssertEqual(32, parsedRes.cgmDataTypeRaw)
        XCTAssertEqual(-2, parsedRes.rate)
        XCTAssertEqual(101, parsedRes.algorithmStateRaw)
        XCTAssertEqual(-59, parsedRes.rssi)
        XCTAssertEqual(261, parsedRes.currentGlucoseDisplayValue)
        XCTAssertEqual(566516504, parsedRes.egvTimestamp)
        XCTAssertEqual(4577, parsedRes.egvInfoBitmaskRaw)
        XCTAssertEqual(1, parsedRes.interval)
    }

    func testCgmDataFsl2HistoryLogEnums() {
        let parsed = HistoryLogParser.parse(CgmDataFsl2HistoryLog(
            pumpTimeSec: 566_516_808, sequenceNum: 506_706,
            glucoseValueStatus: 1, cgmDataType: 32, rate: -2, algorithmState: 101, rssi: -59,
            currentGlucoseDisplayValue: 261, egvTimestamp: 566_516_504, egvInfoBitmask: 0x10E1, interval: 1
        ).cargo) as! CgmDataFsl2HistoryLog
        XCTAssertEqual(.SPECIAL_HIGH, parsed.glucoseValueStatus)
        XCTAssertEqual([.ONE_MINUTE_READING], parsed.cgmDataType)
        XCTAssertEqual(.RF_ERROR, parsed.algorithmState)
        XCTAssertEqual([.FIVE_MINUTE_READING, .VALID_TIMESTAMP, .VALID_EGV_RANGE, .VALID_ALG_STATE], parsed.egvInfo)
        XCTAssertEqual(2, parsed.sensorType)
    }
}
