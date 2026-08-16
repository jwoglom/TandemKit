@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `BolusHeaderNibbleHistoryLogTest`.
///
/// Round-trip coverage for the five bolus history logs when the top 4 bits of the first two cargo
/// bytes are nonzero, so that opCode 55 arrives as `37 10` rather than `37 00`. See
/// `HistoryLogRecord.withHeaderHighNibble` / `HistoryLogRecord.typeIdBytes`: what those bits mean
/// is unknown.
///
/// These fixtures are entirely synthetic (both the field values and the choice of a high nibble of
/// 1 are invented) -- see the Java test's class doc for the full caveat. This port carries that
/// caveat over unchanged.
///
/// Adaptations from the Java original:
/// - The Swift convenience inits don't take a `headerHighNibble` parameter (unlike Java's
///   10/14/8/7/8-arg overloads), so each expected instance is built with the ordinary
///   convenience init and then `.withHeaderHighNibble(1)` is applied, matching the porting rule
///   for this pattern.
/// - There is no `HistoryLog.getHeaderHighNibble()` accessor on the Swift base class, so the
///   nibble is read directly from `cargo[1] >> 4` via a small local helper.
/// - There is no `HistoryLogParser.typeIdOf(...)` helper; `HistoryLog.typeId` already returns the
///   opCode with the high nibble masked off (computed the same way in `HistoryLogRecord.init`), so
///   it is used directly wherever the Java test calls `typeIdOf`.
/// - There is no `HistoryLog.INSULIN_FLOAT_EPSILON` constant; a local constant of the same value
///   (`1e-6`) is used instead.
/// - `BolusRequestedMsg1HistoryLog.BolusType` (INSULIN/CARB/AUTOMATIC_CORRECTION/REMOTE, a scalar
///   enum over `bolusTypeId`) does not exist on the Swift class -- it only exposes an unrelated
///   `bolusType: Set<BolusDeliveryHistoryLog.BolusType>` computed from a bitmask read of the same
///   field, which is a different scheme with different semantics (see
///   `BolusDeliveryHistoryLog.BolusType` for the bitmask this actually reflects). The
///   `testEnumsDecodeFixtureValues` portion asserting `BolusRequestedMsg1HistoryLog.BolusType` is
///   therefore dropped; the `BolusRequestedMsg2HistoryLog.BolusOption`/`SelectedIOBType` portion,
///   which matches Java exactly, is kept.
final class BolusHeaderNibbleHistoryLogTests: XCTestCase {
    private static let highNibble = 1

    // Bolus 2001: BLE-commanded standard bolus, food only.
    private static let b1Msg1 = "40100065cd1da0bb0d00d1070300000000000000000000000000"
    private static let b1Msg2 = "41100065cd1da1bb0d00d1070464000000000000000001000100"
    private static let b1Msg3 = "42100065cd1da2bb0d00d1070000000060400000000000006040"
    private static let b1Activated = "37100265cd1da8bb0d00d1070100000010400000604000000000"
    private static let b1Completed = "14107865cd1db2bb0d000300d1070000b8400000604000006040"

    // Bolus 2002: BLE-commanded standard bolus, food plus a nonzero correction component.
    private static let b2Msg1 = "4010e868cd1d04bc0d00d2070301000000000000000000000000"
    private static let b2Msg2 = "4110e868cd1d05bc0d00d2070464000000000000000001000000"
    private static let b2Msg3 = "4210e868cd1d06bc0d00d2070000000088400000403f0000a040"
    private static let b2Activated = "3710ea68cd1d0cbc0d00d20700000000c03f0000a04000000000"
    private static let b2Completed = "14106069cd1d16bc0d000300d2070000d0400000a0400000a040"

    // Bolus 2003: pump-entered carb bolus, exercising carbAmount/bg/isf/targetBG/carbRatio.
    private static let b3Msg1 = "4010d06ccd1d68bc0d00d30701012d008c000000c03f70170000"
    private static let b3Msg2 = "4110d06ccd1d69bc0d00d3070064000000001e006e0000000100"
    private static let b3Msg3 = "4210d06ccd1d6abc0d00d30700000000f0400000803e0000f840"
    private static let b3Activated = "3710d26ccd1d70bc0d00d30701000000403f0000f84000000000"
    private static let b3Completed = "1410486dcd1d7abc0d000300d307000008410000f8400000f840"

    private static let insulinFloatEpsilon: Float = 1e-6

    private func headerHighNibble(of log: HistoryLog) -> Int {
        Int(log.cargo[log.cargo.startIndex + 1] >> 4) & 0x0F
    }

    private func assertRoundTrip<T: HistoryLog>(
        _ rawHex: String,
        _ expected: T,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let parsed = HistoryLogMessageTester.testSingle(rawHex, expected, file: file, line: line)
        XCTAssertEqual(Self.highNibble, headerHighNibble(of: parsed), file: file, line: line)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo, file: file, line: line)
    }

    func testBolusRequestedMsg1HighNibble() {
        assertRoundTrip(Self.b1Msg1, BolusRequestedMsg1HistoryLog(
            pumpTimeSec: 500000000, sequenceNum: 900000, bolusId: 2001, bolusTypeId: 3,
            correctionBolusIncluded: false, carbAmount: 0, bg: 0, iob: 0.0, carbRatio: 0
        ).withHeaderHighNibble(Self.highNibble))
        assertRoundTrip(Self.b2Msg1, BolusRequestedMsg1HistoryLog(
            pumpTimeSec: 500001000, sequenceNum: 900100, bolusId: 2002, bolusTypeId: 3,
            correctionBolusIncluded: true, carbAmount: 0, bg: 0, iob: 0.0, carbRatio: 0
        ).withHeaderHighNibble(Self.highNibble))
        assertRoundTrip(Self.b3Msg1, BolusRequestedMsg1HistoryLog(
            pumpTimeSec: 500002000, sequenceNum: 900200, bolusId: 2003, bolusTypeId: 1,
            correctionBolusIncluded: true, carbAmount: 45, bg: 140, iob: 1.5, carbRatio: 6000
        ).withHeaderHighNibble(Self.highNibble))
    }

    func testBolusRequestedMsg2HighNibble() {
        assertRoundTrip(Self.b1Msg2, BolusRequestedMsg2HistoryLog(
            pumpTimeSec: 500000000, sequenceNum: 900001, bolusId: 2001, options: 4, standardPercent: 100,
            duration: 0, spare1: 0, isf: 0, targetBG: 0, userOverride: true, declinedCorrection: false,
            selectedIOB: 1, spare2: 0
        ).withHeaderHighNibble(Self.highNibble))
        assertRoundTrip(Self.b2Msg2, BolusRequestedMsg2HistoryLog(
            pumpTimeSec: 500001000, sequenceNum: 900101, bolusId: 2002, options: 4, standardPercent: 100,
            duration: 0, spare1: 0, isf: 0, targetBG: 0, userOverride: true, declinedCorrection: false,
            selectedIOB: 0, spare2: 0
        ).withHeaderHighNibble(Self.highNibble))
        assertRoundTrip(Self.b3Msg2, BolusRequestedMsg2HistoryLog(
            pumpTimeSec: 500002000, sequenceNum: 900201, bolusId: 2003, options: 0, standardPercent: 100,
            duration: 0, spare1: 0, isf: 30, targetBG: 110, userOverride: false, declinedCorrection: false,
            selectedIOB: 1, spare2: 0
        ).withHeaderHighNibble(Self.highNibble))
    }

    func testBolusRequestedMsg3HighNibble() {
        assertRoundTrip(Self.b1Msg3, BolusRequestedMsg3HistoryLog(
            pumpTimeSec: 500000000, sequenceNum: 900002, bolusId: 2001, spare: 0,
            foodBolusSize: 3.5, correctionBolusSize: 0.0, totalBolusSize: 3.5
        ).withHeaderHighNibble(Self.highNibble))
        assertRoundTrip(Self.b2Msg3, BolusRequestedMsg3HistoryLog(
            pumpTimeSec: 500001000, sequenceNum: 900102, bolusId: 2002, spare: 0,
            foodBolusSize: 4.25, correctionBolusSize: 0.75, totalBolusSize: 5.0
        ).withHeaderHighNibble(Self.highNibble))
        assertRoundTrip(Self.b3Msg3, BolusRequestedMsg3HistoryLog(
            pumpTimeSec: 500002000, sequenceNum: 900202, bolusId: 2003, spare: 0,
            foodBolusSize: 7.5, correctionBolusSize: 0.25, totalBolusSize: 7.75
        ).withHeaderHighNibble(Self.highNibble))
    }

    func testBolusActivatedHighNibble() {
        assertRoundTrip(Self.b1Activated, BolusActivatedHistoryLog(
            pumpTimeSec: 500000002, sequenceNum: 900008, bolusId: 2001, selectedIob: 1, iob: 2.25, bolusSize: 3.5
        ).withHeaderHighNibble(Self.highNibble))
        assertRoundTrip(Self.b2Activated, BolusActivatedHistoryLog(
            pumpTimeSec: 500001002, sequenceNum: 900108, bolusId: 2002, selectedIob: 0, iob: 1.5, bolusSize: 5.0
        ).withHeaderHighNibble(Self.highNibble))
        assertRoundTrip(Self.b3Activated, BolusActivatedHistoryLog(
            pumpTimeSec: 500002002, sequenceNum: 900208, bolusId: 2003, selectedIob: 1, iob: 0.75, bolusSize: 7.75
        ).withHeaderHighNibble(Self.highNibble))
    }

    func testBolusCompletedHighNibble() {
        assertRoundTrip(Self.b1Completed, BolusCompletedHistoryLog(
            pumpTimeSec: 500000120, sequenceNum: 900018, completionStatusId: 3, bolusId: 2001,
            iob: 5.75, insulinDelivered: 3.5, insulinRequested: 3.5
        ).withHeaderHighNibble(Self.highNibble))
        assertRoundTrip(Self.b2Completed, BolusCompletedHistoryLog(
            pumpTimeSec: 500001120, sequenceNum: 900118, completionStatusId: 3, bolusId: 2002,
            iob: 6.5, insulinDelivered: 5.0, insulinRequested: 5.0
        ).withHeaderHighNibble(Self.highNibble))
        assertRoundTrip(Self.b3Completed, BolusCompletedHistoryLog(
            pumpTimeSec: 500002120, sequenceNum: 900218, completionStatusId: 3, bolusId: 2003,
            iob: 8.5, insulinDelivered: 7.75, insulinRequested: 7.75
        ).withHeaderHighNibble(Self.highNibble))
    }

    /// A record must reach its class through the primary dispatch path. Before the high nibble was
    /// masked off, opCode 55 with a high nibble of 1 would compute as typeId 4151 and miss
    /// dispatch entirely.
    func testHighNibbleRecordsDispatchToTheCorrectClass() {
        let raw = Data(hexadecimalString: Self.b1Msg1)!
        let parsedMsg1 = HistoryLogParser.parse(raw)
        XCTAssertEqual(Self.highNibble, headerHighNibble(of: parsedMsg1))

        // The typeId the dispatcher looks up must already be the real opCode, so that these
        // records resolve on the first attempt.
        XCTAssertEqual(64, parsedMsg1.typeId)
        XCTAssertEqual(65, HistoryLogParser.parse(Data(hexadecimalString: Self.b1Msg2)!).typeId)
        XCTAssertEqual(66, HistoryLogParser.parse(Data(hexadecimalString: Self.b1Msg3)!).typeId)
        XCTAssertEqual(55, HistoryLogParser.parse(Data(hexadecimalString: Self.b1Activated)!).typeId)
        XCTAssertEqual(20, HistoryLogParser.parse(Data(hexadecimalString: Self.b1Completed)!).typeId)

        XCTAssertTrue(parsedMsg1 is BolusRequestedMsg1HistoryLog)
        XCTAssertTrue(HistoryLogParser.parse(Data(hexadecimalString: Self.b1Msg2)!) is BolusRequestedMsg2HistoryLog)
        XCTAssertTrue(HistoryLogParser.parse(Data(hexadecimalString: Self.b1Msg3)!) is BolusRequestedMsg3HistoryLog)
        XCTAssertTrue(HistoryLogParser.parse(Data(hexadecimalString: Self.b1Activated)!) is BolusActivatedHistoryLog)
        XCTAssertTrue(HistoryLogParser.parse(Data(hexadecimalString: Self.b1Completed)!) is BolusCompletedHistoryLog)
    }

    /// The five logs emitted for a single bolus must agree on the bolusId. This is the property
    /// which distinguishes the correct byte offsets from the alternatives: reading bolusId from the
    /// wrong offset makes at least one of the five disagree with the others.
    func testBolusIdAgreesAcrossAllFiveLogs() {
        assertBolusIdsAgree(2001, Self.b1Msg1, Self.b1Msg2, Self.b1Msg3, Self.b1Activated, Self.b1Completed)
        assertBolusIdsAgree(2002, Self.b2Msg1, Self.b2Msg2, Self.b2Msg3, Self.b2Activated, Self.b2Completed)
        assertBolusIdsAgree(2003, Self.b3Msg1, Self.b3Msg2, Self.b3Msg3, Self.b3Activated, Self.b3Completed)
    }

    /// msg3 reports the food and correction components alongside the total. Compared with a
    /// tolerance, since the pump recomputes the total in float rather than copying the sum.
    func testMsg3ComponentsSumToTotal() {
        for hex in [Self.b1Msg3, Self.b2Msg3, Self.b3Msg3] {
            let msg3 = HistoryLogParser.parse(Data(hexadecimalString: hex)!) as! BolusRequestedMsg3HistoryLog
            XCTAssertEqual(msg3.totalBolusSize, msg3.foodBolusSize + msg3.correctionBolusSize, accuracy: Self.insulinFloatEpsilon)
        }
    }

    /// The dose reported by msg3, by the activated log and by the completed log must agree.
    func testDoseAgreesAcrossLogs() {
        assertDoseAgrees(Self.b1Msg3, Self.b1Activated, Self.b1Completed)
        assertDoseAgrees(Self.b2Msg3, Self.b2Activated, Self.b2Completed)
        assertDoseAgrees(Self.b3Msg3, Self.b3Activated, Self.b3Completed)
    }

    /// byte 12 of the activated log is a field, not padding: it varies independently of the bytes
    /// around it and matches the selectedIOB reported by msg2 for the same bolus.
    func testActivatedSelectedIobIsAField() {
        let first = HistoryLogParser.parse(Data(hexadecimalString: Self.b1Activated)!) as! BolusActivatedHistoryLog
        let second = HistoryLogParser.parse(Data(hexadecimalString: Self.b2Activated)!) as! BolusActivatedHistoryLog
        XCTAssertNotEqual(first.selectedIob, second.selectedIob)

        XCTAssertEqual(msg2Of(Self.b1Msg2).selectedIOB, first.selectedIob)
        XCTAssertEqual(msg2Of(Self.b2Msg2).selectedIOB, second.selectedIob)
    }

    /// Only the `BolusRequestedMsg2HistoryLog.BolusOption`/`SelectedIOBType` portion of Java's
    /// `testEnumsDecodeFixtureValues` is ported; see the class doc for why the
    /// `BolusRequestedMsg1HistoryLog.BolusType` portion is dropped.
    func testEnumsDecodeFixtureValues() {
        XCTAssertEqual(BolusRequestedMsg2HistoryLog.BolusOption.bleStandard, msg2Of(Self.b1Msg2).bolusOption)
        XCTAssertEqual(BolusRequestedMsg2HistoryLog.BolusOption.standard, msg2Of(Self.b3Msg2).bolusOption)

        XCTAssertEqual(BolusRequestedMsg2HistoryLog.SelectedIOBType.swanIOBMeal, msg2Of(Self.b1Msg2).selectedIOBType)
        XCTAssertEqual(BolusRequestedMsg2HistoryLog.SelectedIOBType.mudaliarIOB, msg2Of(Self.b2Msg2).selectedIOBType)
    }

    private func msg2Of(_ hex: String) -> BolusRequestedMsg2HistoryLog {
        HistoryLogParser.parse(Data(hexadecimalString: hex)!) as! BolusRequestedMsg2HistoryLog
    }

    private func assertDoseAgrees(_ msg3Hex: String, _ activatedHex: String, _ completedHex: String) {
        let total = (HistoryLogParser.parse(Data(hexadecimalString: msg3Hex)!) as! BolusRequestedMsg3HistoryLog).totalBolusSize
        let activated = (HistoryLogParser.parse(Data(hexadecimalString: activatedHex)!) as! BolusActivatedHistoryLog).bolusSize
        let requested = (HistoryLogParser.parse(Data(hexadecimalString: completedHex)!) as! BolusCompletedHistoryLog).insulinRequested

        XCTAssertEqual(total, activated, accuracy: Self.insulinFloatEpsilon)
        XCTAssertEqual(total, requested, accuracy: Self.insulinFloatEpsilon)
    }

    private func assertBolusIdsAgree(
        _ expectedBolusId: Int,
        _ msg1Hex: String,
        _ msg2Hex: String,
        _ msg3Hex: String,
        _ activatedHex: String,
        _ completedHex: String
    ) {
        XCTAssertEqual(expectedBolusId, (HistoryLogParser.parse(Data(hexadecimalString: msg1Hex)!) as! BolusRequestedMsg1HistoryLog).bolusId)
        XCTAssertEqual(expectedBolusId, msg2Of(msg2Hex).bolusId)
        XCTAssertEqual(expectedBolusId, (HistoryLogParser.parse(Data(hexadecimalString: msg3Hex)!) as! BolusRequestedMsg3HistoryLog).bolusId)
        XCTAssertEqual(expectedBolusId, (HistoryLogParser.parse(Data(hexadecimalString: activatedHex)!) as! BolusActivatedHistoryLog).bolusId)
        XCTAssertEqual(expectedBolusId, (HistoryLogParser.parse(Data(hexadecimalString: completedHex)!) as! BolusCompletedHistoryLog).bolusId)
    }
}
