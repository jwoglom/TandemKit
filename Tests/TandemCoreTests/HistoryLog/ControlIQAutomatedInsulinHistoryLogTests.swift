@testable import TandemKit
import XCTest

final class ControlIQAutomatedInsulinHistoryLogTests: XCTestCase {
    private func parse(_ hex: String, _ expected: ControlIQAutomatedInsulinHistoryLog, file: StaticString = #file, line: UInt = #line) -> ControlIQAutomatedInsulinHistoryLog {
        let parsed = HistoryLogMessageTester.testSingle(hex, expected, file: file, line: line)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        return parsed
    }

    func testAutoBolusInWindowTslimX2() {
        // Maintainer's t:slim X2 (2024). A 0.823 U automatic bolus started 9 minutes earlier.
        let parsed = parse(
            "ed00b300da1f072c100084ff0a400000bc360ed0523f00000000",
            ControlIQAutomatedInsulinHistoryLog(
                pumpTimeSec: 534380723,
                sequenceNum: 1059847,
                totalInsulin: 2.1718454,
                basalAboveProfileInsulin: 5.6028366e-06,
                autoBolusInsulin: 0.82348716,
                unknown22: 0
            )
        )
        XCTAssertEqual(0.823, parsed.autoBolusInsulin, accuracy: 0.0005)
        XCTAssertEqual(1.3483579, parsed.basalInsulin, accuracy: 0.00001)
        XCTAssertLessThan(abs(parsed.basalAboveProfileInsulin), ControlIQAutomatedInsulinHistoryLog.residueThresholdUnits)
        XCTAssertTrue(parsed.hasAutomatedInsulin)
        XCTAssertEqual(0, parsed.unknown22)
    }

    func testAutoBolusLeavesWindowAfterTwoHoursTslimX2() {
        // Maintainer's t:slim X2 (2024), same pump and automatic bolus as testAutoBolusInWindowTslimX2.
        let before = parse(
            "ed002ffdd91fae2b1000fe96ac3f0000bc36000080b400000000",
            ControlIQAutomatedInsulinHistoryLog(pumpTimeSec: 534379823, sequenceNum: 1059758, totalInsulin: 1.3483579, basalAboveProfileInsulin: 5.6028366e-06, autoBolusInsulin: -2.3841858e-07, unknown22: 0)
        )
        let booked = parse(
            "ed00b300da1f072c100084ff0a400000bc360ed0523f00000000",
            ControlIQAutomatedInsulinHistoryLog(pumpTimeSec: 534380723, sequenceNum: 1059847, totalInsulin: 2.1718454, basalAboveProfileInsulin: 5.6028366e-06, autoBolusInsulin: 0.82348716, unknown22: 0)
        )
        let stillIn = parse(
            "ed004f19da1f472d10004e41ee3f0000bc360ed0523f00000000",
            ControlIQAutomatedInsulinHistoryLog(pumpTimeSec: 534387023, sequenceNum: 1060167, totalInsulin: 1.861368, basalAboveProfileInsulin: 5.6028366e-06, autoBolusInsulin: 0.82348716, unknown22: 0)
        )
        let expired = parse(
            "ed00d31cda1f6d2d100017b7a73f07788b3e000080b400000000",
            ControlIQAutomatedInsulinHistoryLog(pumpTimeSec: 534387923, sequenceNum: 1060205, totalInsulin: 1.310275, basalAboveProfileInsulin: 0.2724001, autoBolusInsulin: -2.3841858e-07, unknown22: 0)
        )

        XCTAssertLessThan(abs(before.autoBolusInsulin), ControlIQAutomatedInsulinHistoryLog.residueThresholdUnits)
        XCTAssertEqual(6300, stillIn.pumpTimeSec - booked.pumpTimeSec)
        XCTAssertEqual(booked.autoBolusInsulin, stillIn.autoBolusInsulin)
        XCTAssertEqual(7200, expired.pumpTimeSec - booked.pumpTimeSec)
        XCTAssertLessThan(abs(expired.autoBolusInsulin), ControlIQAutomatedInsulinHistoryLog.residueThresholdUnits)
        XCTAssertEqual(before.autoBolusInsulin, expired.autoBolusInsulin)
    }

    func testBasalAboveProfileAndAutoBolusTslimX2From2022() {
        // Maintainer's t:slim X2 (2022). A 1.555 U automatic bolus 8 minutes earlier; basal also ran above profile.
        let parsed = parse(
            "ed00c5bc961a87cf0200e3512f4022c75c3e7001c73f00000000",
            ControlIQAutomatedInsulinHistoryLog(
                pumpTimeSec: 446086341,
                sequenceNum: 184199,
                totalInsulin: 2.739373,
                basalAboveProfileInsulin: 0.21560338,
                autoBolusInsulin: 1.5547314,
                unknown22: 0
            )
        )
        XCTAssertEqual(1.555, parsed.autoBolusInsulin, accuracy: 0.0005)
        XCTAssertEqual(0.2156, parsed.basalAboveProfileInsulin, accuracy: 0.0001)
        XCTAssertEqual(0.9690, parsed.totalInsulin - parsed.basalAboveProfileInsulin - parsed.autoBolusInsulin, accuracy: 0.0001)
    }

    func testClosedLoopWithoutAutoBolusTslimX2() {
        // Maintainer's t:slim X2 (a second pump, 2024).
        let parsed = parse(
            "ed007113651e83fa23005c09354063cea53f0000000000000000",
            ControlIQAutomatedInsulinHistoryLog(
                pumpTimeSec: 509940593,
                sequenceNum: 2357891,
                totalInsulin: 2.8286963,
                basalAboveProfileInsulin: 1.2953609,
                autoBolusInsulin: 0,
                unknown22: 0
            )
        )
        XCTAssertEqual(0, parsed.autoBolusInsulin)
        XCTAssertEqual(parsed.totalInsulin, parsed.basalInsulin)
        XCTAssertLessThan(parsed.basalAboveProfileInsulin, parsed.totalInsulin)
        XCTAssertTrue(parsed.hasAutomatedInsulin)
    }

    func testClosedLoopMobi() {
        // Maintainer's Tandem Mobi (2025).
        let parsed = parse(
            "ed10d1d02720b49e0100eedbfc3fb464073f0000203500000000",
            ControlIQAutomatedInsulinHistoryLog(
                pumpTimeSec: 539480273,
                sequenceNum: 106164,
                totalInsulin: 1.9754617,
                basalAboveProfileInsulin: 0.52888036,
                autoBolusInsulin: 5.9604645e-07,
                unknown22: 0
            ).withHeaderHighNibble(1)
        )
        XCTAssertEqual(0.5289, parsed.basalAboveProfileInsulin, accuracy: 0.0001)
        XCTAssertLessThan(abs(parsed.autoBolusInsulin), ControlIQAutomatedInsulinHistoryLog.residueThresholdUnits)
        XCTAssertTrue(parsed.hasAutomatedInsulin)
    }

    func testControlIqOffMobi() {
        // Maintainer's Tandem Mobi (7.9.0.2), never in closed loop since the pump started.
        let zero = parse(
            "ed1088672c23bc3c0a0000000000000000000000000000000000",
            ControlIQAutomatedInsulinHistoryLog(pumpTimeSec: 590112648, sequenceNum: 670908, totalInsulin: 0, basalAboveProfileInsulin: 0, autoBolusInsulin: 0, unknown22: 0)
                .withHeaderHighNibble(1)
        )
        XCTAssertEqual(0, zero.totalInsulin)
        XCTAssertEqual(0, zero.basalAboveProfileInsulin)
        XCTAssertEqual(0, zero.autoBolusInsulin)
        XCTAssertFalse(zero.hasAutomatedInsulin)

        // Maintainer's Tandem Mobi (2026), Control-IQ off for days after earlier closed-loop use.
        let residue = parse(
            "ed1040e6de220c8209000000b4b5000040340000000000000000",
            ControlIQAutomatedInsulinHistoryLog(pumpTimeSec: 585033280, sequenceNum: 623116, totalInsulin: -1.3411045e-06, basalAboveProfileInsulin: 1.7881393e-07, autoBolusInsulin: 0, unknown22: 0)
                .withHeaderHighNibble(1)
        )
        XCTAssertNotEqual(0, residue.totalInsulin)
        XCTAssertFalse(residue.hasAutomatedInsulin)
    }
}
