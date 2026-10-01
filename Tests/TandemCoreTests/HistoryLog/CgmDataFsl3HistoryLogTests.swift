@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `CgmDataFsl3HistoryLogTest`. The fixture follows the Tandem Source event schema
/// layout for this record: status u8 @0, data type u8 @1, rate s16 @2, algorithm state u8 @4,
/// rssi s8 @5, value u16 @6, timestamp u32 @8, EGV info u16 @12, interval u8 @14.
final class CgmDataFsl3HistoryLogTests: XCTestCase {
    func testCgmDataFsl3HistoryLogParse() {
        let expected = CgmDataFsl3HistoryLog(
            pumpTimeSec: 566516507,
            sequenceNum: 506696,
            glucoseValueStatus: 2,
            cgmDataType: 2,
            rate: 7,
            algorithmState: 100,
            rssi: -70,
            currentGlucoseDisplayValue: 60,
            egvTimestamp: 566516504,
            egvInfoBitmask: 8418,
            interval: 1
        )

        let rawHex = "e0011b5bc42148bb07000202070064ba3c00185bc421e2200100"
        XCTAssertEqual(rawHex, expected.cargo.hexadecimalString)

        let parsedRes = HistoryLogMessageTester.testSingle(rawHex, expected)
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)

        XCTAssertEqual(expected.pumpTimeSec, parsedRes.pumpTimeSec)
        XCTAssertEqual(expected.sequenceNum, parsedRes.sequenceNum)
        XCTAssertEqual(2, parsedRes.glucoseValueStatusRaw)
        XCTAssertEqual(2, parsedRes.cgmDataTypeRaw)
        XCTAssertEqual(7, parsedRes.rate)
        XCTAssertEqual(100, parsedRes.algorithmStateRaw)
        XCTAssertEqual(-70, parsedRes.rssi)
        XCTAssertEqual(60, parsedRes.currentGlucoseDisplayValue)
        XCTAssertEqual(566516504, parsedRes.egvTimestamp)
        XCTAssertEqual(8418, parsedRes.egvInfoBitmaskRaw)
        XCTAssertEqual(1, parsedRes.interval)
    }

    func testCgmDataFsl3HistoryLogEnums() {
        let parsed = HistoryLogParser.parse(CgmDataFsl3HistoryLog(
            pumpTimeSec: 566_516_507, sequenceNum: 506_696,
            glucoseValueStatus: 2, cgmDataType: 2, rate: 7, algorithmState: 100, rssi: -70,
            currentGlucoseDisplayValue: 60, egvTimestamp: 566_516_504, egvInfoBitmask: 0x20E2, interval: 1
        ).cargo) as! CgmDataFsl3HistoryLog
        XCTAssertEqual(.SPECIAL_LOW, parsed.glucoseValueStatus)
        XCTAssertEqual([.BACKFILL], parsed.cgmDataType)
        XCTAssertEqual(.OK, parsed.algorithmState)
        XCTAssertEqual(4, parsed.sensorType)
    }
}
