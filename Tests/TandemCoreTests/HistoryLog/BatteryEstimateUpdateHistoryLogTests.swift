@testable import TandemKit
import XCTest

final class BatteryEstimateUpdateHistoryLogTests: XCTestCase {
    func testOneStepSequenceStart() {
        // Maintainer's Tandem Mobi: a one-step sequence.
        let expected = BatteryEstimateUpdateHistoryLog(
            pumpTimeSec: 589535285,
            sequenceNum: 641089,
            unknown10: 1,
            unknown11: 0,
            currentBatteryAbc: 85,
            unknown13: 136,
            unknown14: 0,
            lipoMv: 4043,
            currentBatteryIbc: 85,
            elapsedMs: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "4a113598232341c80900010055880000cb0f5500000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(136, parsed.unknown13)
    }

    func testOneStepSequenceEnd() {
        let expected = BatteryEstimateUpdateHistoryLog(
            pumpTimeSec: 589535315,
            sequenceNum: 641092,
            unknown10: 0,
            unknown11: 0,
            currentBatteryAbc: 85,
            unknown13: 85,
            unknown14: 0,
            lipoMv: 4043,
            currentBatteryIbc: 85,
            elapsedMs: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "4a115398232344c80900000055550000cb0f5500000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testThreeCycleSequenceStart() {
        // Maintainer's Tandem Mobi: abc went 54 -> 61; CurrentBatteryV2Response 1 second after the final record read abc 61.
        let expected = BatteryEstimateUpdateHistoryLog(
            pumpTimeSec: 590938802,
            sequenceNum: 715272,
            unknown10: 1,
            unknown11: 0,
            currentBatteryAbc: 54,
            unknown13: 61,
            unknown14: 0,
            lipoMv: 3864,
            currentBatteryIbc: 45,
            elapsedMs: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "4a11b202392308ea0a000100363d0000180f2d00000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(54, parsed.currentBatteryAbc)
        XCTAssertEqual(61, parsed.unknown13)
    }

    func testThreeCycleSequenceStep3() {
        let expected = BatteryEstimateUpdateHistoryLog(
            pumpTimeSec: 590938862,
            sequenceNum: 715276,
            unknown10: 3,
            unknown11: 1,
            currentBatteryAbc: 54,
            unknown13: 61,
            unknown14: 0,
            lipoMv: 3864,
            currentBatteryIbc: 45,
            elapsedMs: 60630
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "4a11ee0239230cea0a000301363d0000180f2d000000d6ec0000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(60630, parsed.elapsedMs)
        XCTAssertEqual(1, parsed.unknown11)
    }

    func testThreeCycleSequenceEnd() {
        let expected = BatteryEstimateUpdateHistoryLog(
            pumpTimeSec: 590938990,
            sequenceNum: 715287,
            unknown10: 0,
            unknown11: 0,
            currentBatteryAbc: 61,
            unknown13: 61,
            unknown14: 0,
            lipoMv: 3864,
            currentBatteryIbc: 45,
            elapsedMs: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "4a116e03392317ea0a0000003d3d0000180f2d00000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(61, parsed.currentBatteryAbc)
    }

    func testTslimX2Step2() {
        // Maintainer's t:slim X2.
        let expected = BatteryEstimateUpdateHistoryLog(
            pumpTimeSec: 461579488,
            sequenceNum: 25461,
            unknown10: 2,
            unknown11: 0,
            currentBatteryAbc: 99,
            unknown13: 99,
            unknown14: 0,
            lipoMv: 4166,
            currentBatteryIbc: 100,
            elapsedMs: 30000
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "4a01e024831b7563000002006363000046106400000030750000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(30000, parsed.elapsedMs)
    }
}
