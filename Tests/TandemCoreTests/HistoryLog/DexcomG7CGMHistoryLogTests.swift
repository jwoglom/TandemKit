@testable import TandemKit
import XCTest

/// Bluetooth comm sent history logs are little-endian.
/// But Tandem Source appears to store/process them as big-endian, see tconnectsync code.
/// This means that history log strings between the two are not directly comparable.
final class DexcomG7CGMHistoryLogTests: XCTestCase {
    func testDexcomG7CGMHistoryLog1() {
        let expected = DexcomG7CGMHistoryLog(
            pumpTimeSec: 566516808,
            sequenceNum: 506706,
            glucoseValueStatus: 0,
            cgmDataType: 1,
            rate: 4,
            algorithmState: 32,
            rssi: -61,
            currentGlucoseDisplayValue: 257,
            egvTimestamp: 566516805,
            egvInfoBitmask: 6625,
            interval: 0
        )

        let parsedRes = HistoryLogMessageTester.testSingle(
            "8f11485cc42152bb07000000010420c30101455cc421e1190000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
        XCTAssertEqual(parsedRes.egvCount, 0)
        XCTAssertEqual(parsedRes.egvSensorType, .dexcomG7)
    }

    func testDexcomG7CGMHistoryLog2() {
        let expected = DexcomG7CGMHistoryLog(
            pumpTimeSec: 566516507,
            sequenceNum: 506696,
            glucoseValueStatus: 0,
            cgmDataType: 1,
            rate: 13,
            algorithmState: 32,
            rssi: -59,
            currentGlucoseDisplayValue: 261,
            egvTimestamp: 566516504,
            egvInfoBitmask: 6625,
            interval: 0
        )

        let parsedRes = HistoryLogMessageTester.testSingle(
            "8f111b5bc42148bb07000000010d20c50501185bc421e1190000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
    }

    func testDexcomG7CGMHistoryLog3() {
        let expected = DexcomG7CGMHistoryLog(
            pumpTimeSec: 566516207,
            sequenceNum: 506647,
            glucoseValueStatus: 0,
            cgmDataType: 1,
            rate: 20,
            algorithmState: 32,
            rssi: -65,
            currentGlucoseDisplayValue: 265,
            egvTimestamp: 566516204,
            egvInfoBitmask: 6625,
            interval: 0
        )

        let parsedRes = HistoryLogMessageTester.testSingle(
            "8f11ef59c42117bb07000000011420bf0901ec59c421e1190000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
    }

    func testDexcomG7CGMHistoryLog4() {
        let expected = DexcomG7CGMHistoryLog(
            pumpTimeSec: 566515908,
            sequenceNum: 506634,
            glucoseValueStatus: 0,
            cgmDataType: 1,
            rate: 18,
            algorithmState: 32,
            rssi: -64,
            currentGlucoseDisplayValue: 251,
            egvTimestamp: 566515905,
            egvInfoBitmask: 6625,
            interval: 0
        )

        let parsedRes = HistoryLogMessageTester.testSingle(
            "8f11c458c4210abb07000000011220c0fb00c158c421e1190000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
    }

    func testDexcomG7CGMHistoryLogEgvCountRoundTrip() {
        let log = DexcomG7CGMHistoryLog(
            pumpTimeSec: 566_516_808,
            sequenceNum: 506_707,
            glucoseValueStatus: 0,
            cgmDataType: 1,
            rate: -5,
            algorithmState: 32,
            rssi: -61,
            currentGlucoseDisplayValue: 140,
            egvTimestamp: 566_516_805,
            egvInfoBitmask: 0x19E1,
            interval: 0,
            egvCount: 3
        )

        XCTAssertEqual(log.cargo.count, 26)
        XCTAssertEqual(log.cargo[25], 3)
        let parsed = DexcomG7CGMHistoryLog(cargo: log.cargo)
        MessageTester.assertHexEquals(log.cargo, parsed.cargo)
        XCTAssertEqual(parsed.egvCount, 3)
        XCTAssertEqual(parsed.egvSensorType, .dexcomG7)
    }
}
