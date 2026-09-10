@testable import TandemKit
import XCTest

/// Ported from pumpX2's `PumpingSuspendedHistoryLogTest`.
///
/// The Java test builds some `expected` records via the short constructor (pumpTimeSec/sequenceNum
/// default to 0) and compares with `testSingleIgnoringBaseFields`, which clears the parsed record's
/// base fields before comparing. The Swift `HistoryLogMessageTester` has no equivalent helper, so
/// this adapts by constructing `expected` with the pump time / sequence number actually encoded in
/// the fixture (decoded independently from the raw bytes) and asserting full equality via
/// `testSingle` instead — an equivalent assertion.
final class PumpingSuspendedHistoryLogTests: XCTestCase {
    func testPumpingSuspendedHistoryLog1() {
        let expected = PumpingSuspendedHistoryLog(
            pumpTimeSec: 445995051,
            sequenceNum: 181766,
            preSuspendState: 106,
            insulinAmount: 31,
            reasonId: 0,
            rpaTimeout: 0
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "0b002b58951a06c602006a0000001f0000000000000000000000",
            expected
        )
        XCTAssertEqual(PumpingSuspendedHistoryLog.SuspendReason.userAborted, parsed.reason)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testPumpingSuspendedHistoryLog2() {
        let expected = PumpingSuspendedHistoryLog(
            pumpTimeSec: 446031151,
            sequenceNum: 182637,
            preSuspendState: 106,
            insulinAmount: 180,
            reasonId: 0,
            rpaTimeout: 0
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "0b002fe5951a6dc902006a000000b40000000000000000000000",
            expected
        )
        XCTAssertEqual(PumpingSuspendedHistoryLog.SuspendReason.userAborted, parsed.reason)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testPumpingSuspendedHistoryLog3() {
        let expected = PumpingSuspendedHistoryLog(
            pumpTimeSec: 446120123,
            sequenceNum: 185059,
            preSuspendState: 106,
            insulinAmount: 180,
            reasonId: 0,
            rpaTimeout: 0
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "0b00bb40971ae3d202006a000000b40000000000000000000000",
            expected
        )
        XCTAssertEqual(PumpingSuspendedHistoryLog.SuspendReason.userAborted, parsed.reason)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testPumpingSuspendedHistoryLogAlarmReasonWithRpaTimeout() {
        let expected = PumpingSuspendedHistoryLog(
            pumpTimeSec: 587315465,
            sequenceNum: 744310,
            preSuspendState: 106,
            insulinAmount: 150,
            reasonId: 1,
            rpaTimeout: 15
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "0b1009b90123765b0b006a0000009600010f0000000000000000",
            expected
        )
        XCTAssertEqual(587315465, parsed.pumpTimeSec)
        XCTAssertEqual(744310, parsed.sequenceNum)
        XCTAssertEqual(106, parsed.preSuspendState)
        XCTAssertEqual(150, parsed.insulinAmount)
        XCTAssertEqual(PumpingSuspendedHistoryLog.SuspendReason.alarm, parsed.reason)
        XCTAssertEqual(15, parsed.rpaTimeout)
        MessageTester.assertHexEquals(expected.cargo, PumpingSuspendedHistoryLogTests.withoutSourceNibble(parsed.cargo))
    }

    func testPumpingSuspendedHistoryLogUserAbortedWithRpaTimeout() {
        let expected = PumpingSuspendedHistoryLog(
            pumpTimeSec: 587387440,
            sequenceNum: 748755,
            preSuspendState: 106,
            insulinAmount: 105,
            reasonId: 0,
            rpaTimeout: 15
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "0b1030d20223d36c0b006a0000006900000f0000000000000000",
            expected
        )
        XCTAssertEqual(587387440, parsed.pumpTimeSec)
        XCTAssertEqual(748755, parsed.sequenceNum)
        XCTAssertEqual(106, parsed.preSuspendState)
        XCTAssertEqual(105, parsed.insulinAmount)
        XCTAssertEqual(PumpingSuspendedHistoryLog.SuspendReason.userAborted, parsed.reason)
        XCTAssertEqual(15, parsed.rpaTimeout)
        MessageTester.assertHexEquals(expected.cargo, PumpingSuspendedHistoryLogTests.withoutSourceNibble(parsed.cargo))
    }

    // Observed on a Tandem Mobi driven by Trio (Control-IQ off, no CGM paired), Sept 2026 BLE
    // capture. In each record `insulinAmount` matched `InsulinStatusResponse.currentInsulinAmount`
    // polled within two seconds of the suspend (pumpX2 issue #39).
    func testPumpingSuspendedHistoryLogMobiReservoir150() {
        let expected = PumpingSuspendedHistoryLog(
            pumpTimeSec: 589553316,
            sequenceNum: 641936,
            preSuspendState: 106,
            insulinAmount: 150,
            reasonId: 0,
            rpaTimeout: 15
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "0b10a4de232390cb09006a0000009600000f0000000000000000",
            expected
        )
        XCTAssertEqual(589553316, parsed.pumpTimeSec)
        XCTAssertEqual(641936, parsed.sequenceNum)
        XCTAssertEqual(106, parsed.preSuspendState)
        XCTAssertEqual(150, parsed.insulinAmount)
        XCTAssertEqual(PumpingSuspendedHistoryLog.SuspendReason.userAborted, parsed.reason)
        XCTAssertEqual(15, parsed.rpaTimeout)
        MessageTester.assertHexEquals(expected.cargo, PumpingSuspendedHistoryLogTests.withoutSourceNibble(parsed.cargo))
    }

    // Same capture; a nearly empty reservoir just before a cartridge change (the paired resume
    // read 185 afterwards), showing the field follows the pump's reported remaining insulin.
    func testPumpingSuspendedHistoryLogMobiReservoir8() {
        let expected = PumpingSuspendedHistoryLog(
            pumpTimeSec: 589745484,
            sequenceNum: 651659,
            preSuspendState: 106,
            insulinAmount: 8,
            reasonId: 0,
            rpaTimeout: 15
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "0b104ccd26238bf109006a0000000800000f0000000000000000",
            expected
        )
        XCTAssertEqual(589745484, parsed.pumpTimeSec)
        XCTAssertEqual(651659, parsed.sequenceNum)
        XCTAssertEqual(106, parsed.preSuspendState)
        XCTAssertEqual(8, parsed.insulinAmount)
        XCTAssertEqual(PumpingSuspendedHistoryLog.SuspendReason.userAborted, parsed.reason)
        XCTAssertEqual(15, parsed.rpaTimeout)
        MessageTester.assertHexEquals(expected.cargo, PumpingSuspendedHistoryLogTests.withoutSourceNibble(parsed.cargo))
    }

    /// The upper nibble of the second typeId byte identifies the source of the log entry and is
    /// not part of the typeId itself (`typeId` masks it off with `& 0x0FFF`). `buildCargo` has no
    /// source to emit, so it is masked out of the parsed cargo before comparing the two.
    static func withoutSourceNibble(_ cargo: Data) -> Data {
        var out = cargo
        out[out.startIndex + 1] = out[out.startIndex + 1] & 0x0F
        return out
    }
}
