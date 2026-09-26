@testable import TandemKit
import XCTest

final class ControlIQGlucoseModelHistoryLogTests: XCTestCase {
    private func assertPairedWith227(_ hex227: String, _ log: ControlIQGlucoseModelHistoryLog, file: StaticString = #file, line: UInt = #line) {
        guard let raw227 = Data(hexadecimalString: hex227) else {
            XCTFail("invalid hex", file: file, line: line)
            return
        }
        XCTAssertEqual(227, Bytes.readShort(raw227, 0) & 0x0FFF, file: file, line: line)
        XCTAssertEqual(log.pumpTimeSec, Bytes.readUint32(raw227, 2), file: file, line: line)
        XCTAssertEqual(log.sequenceNum - 1, Bytes.readUint32(raw227, 6), file: file, line: line)
        XCTAssertEqual(min(log.filteredGlucose, 255), Int(raw227[20]), file: file, line: line)
        XCTAssertEqual(log.tdiEstimate, Int(raw227[22]), file: file, line: line)
    }

    func testControlIQGlucoseModelX2ControlIQWithCgm() {
        // Maintainer's t:slim X2 (2023), Control-IQ closed loop; last CGM reading 145 mg/dL.
        let expected = ControlIQGlucoseModelHistoryLog(
            pumpTimeSec: 497792406,
            sequenceNum: 1905835,
            tdiEstimate: 50,
            unknown11: 0,
            unknown12: 0,
            shortTermPredictedGlucoseRaw: 15580,
            filteredGlucose: 144,
            unknown18: 0,
            correctionFactor: 0,
            unknown21: 0,
            unknown22: 0,
            unknown24: 0
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "470196b5ab1dab141d0032000000dc3c90000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(50, parsed.tdiEstimate)
        XCTAssertEqual(144, parsed.filteredGlucose)
        XCTAssertEqual(155.80, parsed.shortTermPredictedGlucoseMgdl, accuracy: 0.001)
        XCTAssertEqual(0, parsed.correctionFactor)
        assertPairedWith227("e30096b5ab1daa141d0022007500e940e8030000901e32c800a0", parsed)
    }

    func testControlIQGlucoseModelX2FilteredGlucoseAbove255() {
        // Maintainer's t:slim X2 (2024); last CGM reading 337 mg/dL.
        let expected = ControlIQGlucoseModelHistoryLog(
            pumpTimeSec: 534198333,
            sequenceNum: 1050496,
            tdiEstimate: 83,
            unknown11: 0,
            unknown12: 0,
            shortTermPredictedGlucoseRaw: 33263,
            filteredGlucose: 333,
            unknown18: 0,
            correctionFactor: 0,
            unknown21: 0,
            unknown22: 0,
            unknown24: 0
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "47013d38d71f8007100053000000ef814d010000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(333, parsed.filteredGlucose)
        XCTAssertEqual(332.63, parsed.shortTermPredictedGlucoseMgdl, accuracy: 0.001)
        XCTAssertEqual(83, parsed.tdiEstimate)
        assertPairedWith227("e3003d38d71f7f07100000004200328020034716ff1553c800a0", parsed)
    }

    func testControlIQGlucoseModelMobiControlIQOffCorrectionFactor() {
        // Maintainer's Tandem Mobi (7.9.0.2), Control-IQ disabled, no CGM; the same-second 332 has TDI estimate 74.05.
        let expected = ControlIQGlucoseModelHistoryLog(
            pumpTimeSec: 591098983,
            sequenceNum: 723618,
            tdiEstimate: 74,
            unknown11: 0,
            unknown12: 0,
            shortTermPredictedGlucoseRaw: 8907,
            filteredGlucose: 89,
            unknown18: 0,
            correctionFactor: 24,
            unknown21: 0,
            unknown22: 0,
            unknown24: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "471167743b23a20a0b004a000000cb2259000000180000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(74, parsed.tdiEstimate)
        XCTAssertEqual(24, parsed.correctionFactor)
        XCTAssertEqual(Int((1800 / 74.05).rounded(.down)), parsed.correctionFactor)
        XCTAssertEqual(89, parsed.filteredGlucose)
        XCTAssertEqual(89.07, parsed.shortTermPredictedGlucoseMgdl, accuracy: 0.001)
        let hex227 = "e31067743b23a10a0b00000013007e22a0056a0259184a20c878"
        assertPairedWith227(hex227, parsed)
        XCTAssertEqual(parsed.correctionFactor, Int(Data(hexadecimalString: hex227)![21]))
    }

    func testControlIQGlucoseModelMobiCorrectionFactorCapped() {
        // Maintainer's Tandem Mobi (7.9.0.2); same-second 332 TDI estimate 55.79, so 1800 / TDI = 32.3, held at the profile ISF of 30.
        let expected = ControlIQGlucoseModelHistoryLog(
            pumpTimeSec: 590556271,
            sequenceNum: 694564,
            tdiEstimate: 55,
            unknown11: 0,
            unknown12: 0,
            shortTermPredictedGlucoseRaw: 8965,
            filteredGlucose: 89,
            unknown18: 0,
            correctionFactor: 30,
            unknown21: 0,
            unknown22: 0,
            unknown24: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "47116f2c332324990a00370000000523590000001e0000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(55, parsed.tdiEstimate)
        XCTAssertEqual(30, parsed.correctionFactor)
        XCTAssertGreaterThan(parsed.shortTermPredictedGlucoseMgdl, 89.0)
    }

    func testControlIQGlucoseModelX2AfterReboot() {
        // Maintainer's t:slim X2 (2023), first record after a reboot, before any CGM reading; TDI setting is 75.
        let expected = ControlIQGlucoseModelHistoryLog(
            pumpTimeSec: 503758975,
            sequenceNum: 2107929,
            tdiEstimate: 75,
            unknown11: 0,
            unknown12: 0,
            shortTermPredictedGlucoseRaw: 2000,
            filteredGlucose: 31,
            unknown18: 0,
            correctionFactor: 0,
            unknown21: 0,
            unknown22: 0,
            unknown24: 0
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "47017fc0061e192a20004b000000d0071f000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(75, parsed.tdiEstimate)
        XCTAssertEqual(31, parsed.filteredGlucose)
        XCTAssertEqual(2000, parsed.shortTermPredictedGlucoseRaw)
        XCTAssertEqual(20.0, parsed.shortTermPredictedGlucoseMgdl, accuracy: 0.001)
    }
}
