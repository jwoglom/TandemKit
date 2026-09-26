@testable import TandemKit
import XCTest

final class ControlIQCycleHistoryLogTests: XCTestCase {
    private func expectedHypoBrake(_ predictedGlucoseMgdl: Double) -> Int {
        guard predictedGlucoseMgdl >= 70 else { return 0 }
        let f = 1.509 * (pow(log(predictedGlucoseMgdl), 1.084) - 5.381)
        let risk = f < 0 ? 10 * f * f : 0
        return Int(floor(200 / (1 + 2.5 * risk) + 1e-9))
    }

    private func parse<T: HistoryLog>(_ hex: String) -> T? {
        HistoryLogParser.parse(Data(hexadecimalString: hex)!) as? T
    }

    func testX2AutoBolusCycle() {
        // Maintainer's t:slim X2 (2024), Control-IQ on with CGM.
        let expected = ControlIQCycleHistoryLog(
            pumpTimeSec: 534192321,
            sequenceNum: 1050055,
            basalIncreaseMilliunits: 74,
            cycleInsulinMilliunits: 913,
            predictedGlucoseX100: 22517,
            programmedBasalRate: 800,
            netIobMilliunits: 2553,
            glucoseEstimate: 180,
            correctionFactor: 21,
            tdiEstimate: 82,
            hypoBrake: 200,
            sleepRamp: 0,
            upperTarget: 160
        )

        let parsed = HistoryLogMessageTester.testSingle("e300c120d71fc70510004a009103f5572003f909b41552c800a0", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)

        let basal: BasalDeliveryHistoryLog? = parse("17011c21d71fcb05100003000100a1062003a106ffff00000000")
        XCTAssertEqual(1697, basal?.algorithmRate)
        XCTAssertEqual(basal?.profileBasalRate, parsed.programmedBasalRate)
        XCTAssertEqual((1697 - 800) / 12, parsed.basalIncreaseMilliunits)

        let bolus: BolusDeliveryHistoryLog? = parse("18013821d71fd8051000110e0109071104030000040300000000")
        XCTAssertEqual(7, bolus?.bolusSource)
        XCTAssertEqual(772, bolus?.requestedNow)
        XCTAssertEqual(1697 / 12 + 772, parsed.cycleInsulinMilliunits)

        XCTAssertEqual(225.17, parsed.predictedGlucoseMgdl, accuracy: 1e-9)
        XCTAssertEqual(expectedHypoBrake(parsed.predictedGlucoseMgdl), parsed.hypoBrake)
        XCTAssertEqual(1.0, parsed.hypoBrakeFraction, accuracy: 1e-9)
    }

    func testX2SleepRampAndBrake() {
        // Maintainer's t:slim X2 (2023), Control-IQ on with CGM, about 80 minutes into sleep mode.
        let expected = ControlIQCycleHistoryLog(
            pumpTimeSec: 497757999,
            sequenceNum: 1904228,
            basalIncreaseMilliunits: 0,
            cycleInsulinMilliunits: 38,
            predictedGlucoseX100: 10275,
            programmedBasalRate: 800,
            netIobMilliunits: 158,
            glucoseEstimate: 119,
            correctionFactor: 30,
            tdiEstimate: 56,
            hypoBrake: 116,
            sleepRamp: 83,
            upperTarget: 120
        )

        let parsed = HistoryLogMessageTester.testSingle("e3002f2fab1d640e1d0000002600232820039e00771e38745378", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)

        XCTAssertEqual(102.75, parsed.predictedGlucoseMgdl, accuracy: 1e-9)
        XCTAssertEqual(expectedHypoBrake(parsed.predictedGlucoseMgdl), parsed.hypoBrake)
        XCTAssertEqual(0.58, parsed.hypoBrakeFraction, accuracy: 1e-9)

        let basal: BasalDeliveryHistoryLog? = parse("1701702fab1d680e1d0003000000d3012003d301ffff00000000")
        XCTAssertEqual(467, basal?.algorithmRate)
        XCTAssertEqual(basal?.profileBasalRate, parsed.programmedBasalRate)
        XCTAssertEqual(467 / 12, parsed.cycleInsulinMilliunits)
        XCTAssertEqual(0, parsed.basalIncreaseMilliunits)

        XCTAssertEqual(83, parsed.sleepRamp)
        XCTAssertEqual(120, parsed.upperTarget)
    }

    func testMobiControlIqOn() {
        // Maintainer's Tandem Mobi (Control-IQ v7.7.0.1), Control-IQ on with CGM, just after sleep mode started.
        let expected = ControlIQCycleHistoryLog(
            pumpTimeSec: 539480071,
            sequenceNum: 106155,
            basalIncreaseMilliunits: 0,
            cycleInsulinMilliunits: 65,
            predictedGlucoseX100: 11101,
            programmedBasalRate: 800,
            netIobMilliunits: 793,
            glucoseEstimate: 136,
            correctionFactor: 25,
            tdiEstimate: 71,
            hypoBrake: 196,
            sleepRamp: 16,
            upperTarget: 159
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle("e31007d02720ab9e0100000041005d2b20031903881947c4109f", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)

        XCTAssertEqual(expectedHypoBrake(parsed.predictedGlucoseMgdl), parsed.hypoBrake)

        let basal: BasalDeliveryHistoryLog? = parse("171125d02720ae9e010003000000140320031403ffff00000000")
        XCTAssertEqual(788, basal?.algorithmRate)
        XCTAssertEqual(basal?.profileBasalRate, parsed.programmedBasalRate)
        XCTAssertEqual(788 / 12, parsed.cycleInsulinMilliunits)

        XCTAssertEqual(16, parsed.sleepRamp)
        XCTAssertEqual(159, parsed.upperTarget)
    }

    func testMobiControlIqOffNoCgm() {
        // Maintainer's Tandem Mobi (7.9.0.2), Control-IQ off, no CGM paired to the pump, sleep mode, temp rate running.
        let expected = ControlIQCycleHistoryLog(
            pumpTimeSec: 590115570,
            sequenceNum: 671012,
            basalIncreaseMilliunits: 0,
            cycleInsulinMilliunits: 19,
            predictedGlucoseX100: 8065,
            programmedBasalRate: 2500,
            netIobMilliunits: 3956,
            glucoseEstimate: 89,
            correctionFactor: 29,
            tdiEstimate: 60,
            hypoBrake: 18,
            sleepRamp: 200,
            upperTarget: 120
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle("e310f2722c23243d0a0000001300811fc409740f591d3c12c878", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)

        let basal: BasalDeliveryHistoryLog? = parse("171110732c23273d0a0002000300c409e803ffffc40900000000")
        XCTAssertEqual(2500, basal?.tempRate)
        XCTAssertEqual(basal?.tempRate, parsed.programmedBasalRate)
        XCTAssertEqual(0, parsed.basalIncreaseMilliunits)

        XCTAssertEqual(80.65, parsed.predictedGlucoseMgdl, accuracy: 1e-9)
        XCTAssertEqual(expectedHypoBrake(parsed.predictedGlucoseMgdl), parsed.hypoBrake)
        let f = 1.509 * (pow(log(80.65), 1.084) - 5.381)
        let brake = 1 / (1 + 2.5 * 10 * f * f)
        XCTAssertEqual(Int(floor(2500 / 12.0 * brake)), parsed.cycleInsulinMilliunits)

        // AaTdiEstChange (332) written in the same second, just before this record.
        let tdi = Bytes.readFloat(Data(hexadecimalString: "4c11f2722c23233d0a00956f7042698f70423c00000000000000")!, 10)
        XCTAssertEqual(Int(floor(tdi)), parsed.tdiEstimate)
        XCTAssertEqual(Int(floor(1800 / tdi)), parsed.correctionFactor)

        XCTAssertEqual(200, parsed.sleepRamp)
        XCTAssertEqual(120, parsed.upperTarget)
    }

    func testMobiBrakeZeroBelow70() {
        // Maintainer's other Tandem Mobi (7.9.0.1), Control-IQ off, no CGM paired to the pump, normal mode.
        let expected = ControlIQCycleHistoryLog(
            pumpTimeSec: 585032868,
            sequenceNum: 623097,
            basalIncreaseMilliunits: 0,
            cycleInsulinMilliunits: 0,
            predictedGlucoseX100: 3096,
            programmedBasalRate: 1500,
            netIobMilliunits: 439,
            glucoseEstimate: 42,
            correctionFactor: 21,
            tdiEstimate: 82,
            hypoBrake: 0,
            sleepRamp: 0,
            upperTarget: 160
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle("e310a4e4de22f981090000000000180cdc05b7012a15520000a0", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)

        let basal: BasalDeliveryHistoryLog? = parse("1711c2e4de22fb81090002000300dc05e803ffffdc0500000000")
        XCTAssertEqual(basal?.tempRate, parsed.programmedBasalRate)

        XCTAssertEqual(30.96, parsed.predictedGlucoseMgdl, accuracy: 1e-9)
        XCTAssertEqual(0, expectedHypoBrake(parsed.predictedGlucoseMgdl))
        XCTAssertEqual(0, parsed.hypoBrake)
        XCTAssertEqual(0.0, parsed.hypoBrakeFraction, accuracy: 1e-9)
        XCTAssertEqual(0, parsed.cycleInsulinMilliunits)

        XCTAssertEqual(0, parsed.sleepRamp)
        XCTAssertEqual(160, parsed.upperTarget)
    }
}
