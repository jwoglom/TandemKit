@testable import TandemCore
import XCTest

final class BolusCalcDataSnapshotResponseTests: XCTestCase {
    func testBolusCalcDataSnapshotResponseWithBolusConstraints() {
        let expected = BolusCalcDataSnapshotResponse(
            isUnacked: false,
            correctionFactor: 209,
            iob: 2937,
            cartridgeRemainingInsulin: 120,
            targetBg: 110,
            isf: 30,
            carbEntryEnabled: true,
            carbRatio: 6000,
            maxBolusAmount: 25000,
            maxBolusHourlyTotal: 2810,
            maxBolusEventsExceeded: false,
            maxIobEventsExceeded: false,
            isAutopopAllowed: true,
            unknown11bytes: Data([0x90, 0xA9, 0x54, 0x1B, 0xDD, 0x0F, 0x00, 0x00, 0x01, 0xFB, 0x01]),
            unknown8bytes: Data([0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55])
        )

        let parsed: BolusCalcDataSnapshotResponse = MessageTester.test(
            "000373032e00d100790b000078006e001e000170170000a861fa0a0000000090a9541bdd0f000001fb0101555555555555555571b3",
            3,
            3,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertFalse(parsed.isUnacked)
        XCTAssertEqual(209, parsed.correctionFactor)
        XCTAssertEqual(2937, parsed.iob)
        XCTAssertEqual(120, parsed.cartridgeRemainingInsulin)
        XCTAssertEqual(110, parsed.targetBg)
        XCTAssertEqual(30, parsed.isf)
        XCTAssertTrue(parsed.carbEntryEnabled)
        XCTAssertEqual(6000, parsed.carbRatio)
        XCTAssertEqual(25000, parsed.maxBolusAmount)
        XCTAssertEqual(2810, parsed.maxBolusHourlyTotal)
        XCTAssertTrue(parsed.isAutopopAllowed)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testBolusCalcDataSnapshotResponseWithZeroHourlyTotal() {
        let expected = BolusCalcDataSnapshotResponse(
            isUnacked: false,
            correctionFactor: 174,
            iob: 2302,
            cartridgeRemainingInsulin: 120,
            targetBg: 110,
            isf: 30,
            carbEntryEnabled: true,
            carbRatio: 6000,
            maxBolusAmount: 25000,
            maxBolusHourlyTotal: 0,
            maxBolusEventsExceeded: false,
            maxIobEventsExceeded: false,
            isAutopopAllowed: true,
            unknown11bytes: Data([0x40, 0xAE, 0x54, 0x1B, 0x8D, 0x14, 0x00, 0x00, 0x01, 0xF0, 0x01]),
            unknown8bytes: Data([0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55])
        )

        let parsed: BolusCalcDataSnapshotResponse = MessageTester.test(
            "000473042e00ae00fe08000078006e001e000170170000a86100000000000040ae541b8d14000001f001015555555555555555d2d7",
            4,
            3,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(0, parsed.maxBolusHourlyTotal)
        XCTAssertEqual(Data([0x40, 0xAE, 0x54, 0x1B, 0x8D, 0x14, 0x00, 0x00, 0x01, 0xF0, 0x01]), parsed.unknown11bytes)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
