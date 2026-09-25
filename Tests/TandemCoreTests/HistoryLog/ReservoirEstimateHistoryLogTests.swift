@testable import TandemKit
import XCTest

final class ReservoirEstimateHistoryLogTests: XCTestCase {
    private func check(
        _ hex: String,
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        deliveredBits: UInt32,
        remainingBits: UInt32,
        displayed: Int,
        driveCounter: UInt32
    ) {
        let expected = ReservoirEstimateHistoryLog(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            insulinDelivered: Float(bitPattern: deliveredBits),
            insulinRemaining: Float(bitPattern: remainingBits),
            displayedInsulinRemaining: displayed,
            driveCounter: driveCounter
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(hex, expected)
        XCTAssertEqual(pumpTimeSec, parsed.pumpTimeSec)
        XCTAssertEqual(sequenceNum, parsed.sequenceNum)
        XCTAssertEqual(deliveredBits, parsed.insulinDelivered.bitPattern)
        XCTAssertEqual(remainingBits, parsed.insulinRemaining.bitPattern)
        XCTAssertEqual(displayed, parsed.displayedInsulinRemaining)
        XCTAssertEqual(driveCounter, parsed.driveCounter)
        XCTAssertEqual(
            ReservoirEstimateHistoryLog.observedStartEstimate,
            parsed.insulinDelivered + parsed.insulinRemaining,
            accuracy: 0.001
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testAtCartridgeInsertion() {
        check(
            "e710e267312379830a0000000000f2ef4b4300000000f2ff0700",
            pumpTimeSec: 590440418, sequenceNum: 689017,
            deliveredBits: 0x0000_0000, remainingBits: 0x434B_EFF2, displayed: 0, driveCounter: 524274
        )
    }

    func testAfterFillDisplayRoundsToNearestFive() {
        check(
            "e710a7693123e9830a000d03a04190ef3743b9000000cf530800",
            pumpTimeSec: 590440871, sequenceNum: 689129,
            deliveredBits: 0x41A0_030D, remainingBits: 0x4337_EF90, displayed: 185, driveCounter: 545743
        )
    }

    func testBelowFortyUnitsDisplayRoundsDown() {
        check(
            "e71099462d239c470a00e30524433ba81f4227000000bfaf0a00",
            pumpTimeSec: 590169753, sequenceNum: 673692,
            deliveredBits: 0x4324_05E3, remainingBits: 0x421F_A83B, displayed: 39, driveCounter: 700351
        )
    }

    func testIssueExample() {
        check(
            "e7107daf232351c909006d1f504216e817439600000030da0800",
            pumpTimeSec: 589541245, sequenceNum: 641361,
            deliveredBits: 0x4250_1F6D, remainingBits: 0x4317_E816, displayed: 150, driveCounter: 580144
        )
    }

    func testDuringFillDisplayIsZero() {
        check(
            "e710c459242334d209009371b842506edf4200000000ba820900",
            pumpTimeSec: 589584836, sequenceNum: 643636,
            deliveredBits: 0x42B8_7193, remainingBits: 0x42DF_6E50, displayed: 0, driveCounter: 623290
        )
    }
}
