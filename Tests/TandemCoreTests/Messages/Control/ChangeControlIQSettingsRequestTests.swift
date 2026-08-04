@testable import TandemCore
import XCTest

final class ChangeControlIQSettingsRequestTests: XCTestCase {
    func testChangeControlIQSettingsRequest_turnOn_150lbs_75tdu() {
        MessageTester.initPumpState("", 0)
        let expected = ChangeControlIQSettingsRequest(
            enabled: true,
            weight: 150,
            weightUnit: .pounds,
            totalDailyInsulinUnits: 75
        )

        let parsed: ChangeControlIQSettingsRequest = MessageTester.test(
            "0157ca571e019600014b0127eaee1fe2a83a5338",
            87,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00578298cbe960ee83e35b3d3fde85b38d7eba"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertTrue(parsed.enabled)
        XCTAssertEqual(150, parsed.weight)
        XCTAssertEqual(.pounds, parsed.weightUnit)
        XCTAssertEqual(75, parsed.totalDailyInsulinUnits)
        XCTAssertEqual(ChangeControlIQSettingsRequest.defaultTrailingFlag, parsed.trailingFlag)
    }

    func testChangeControlIQSettingsRequest_turnOff_150lbs_75tdu() {
        MessageTester.initPumpState("", 0)
        let expected = ChangeControlIQSettingsRequest(
            enabled: false,
            weight: 150,
            weightUnit: .pounds,
            totalDailyInsulinUnits: 75
        )

        let parsed: ChangeControlIQSettingsRequest = MessageTester.test(
            "015cca5c1e009600014b012ceaee1f556e63dee5",
            92,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "005ce9516bf5a6d77eb884dc557e841663bea5"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertFalse(parsed.enabled)
        XCTAssertEqual(150, parsed.weight)
        XCTAssertEqual(.pounds, parsed.weightUnit)
        XCTAssertEqual(75, parsed.totalDailyInsulinUnits)
    }

    /// The weight unit occupies cargo byte 3 and is what gives the weight meaning.
    /// It used to be hardcoded to pounds, which silently rewrote the stored weight of
    /// anyone whose pump was configured in kilograms.
    func testWeightUnitIsCarriedInCargo() {
        let pounds = ChangeControlIQSettingsRequest(
            enabled: true,
            weight: 150,
            weightUnit: .pounds,
            totalDailyInsulinUnits: 75
        )
        let kilograms = ChangeControlIQSettingsRequest(
            enabled: true,
            weight: 68,
            weightUnit: .kilograms,
            totalDailyInsulinUnits: 75
        )

        XCTAssertEqual("019600014b01", pounds.cargo.hexadecimalString)
        XCTAssertEqual("014400004b01", kilograms.cargo.hexadecimalString)
        XCTAssertEqual(ControlIQWeightUnit.pounds.rawValue, Int(pounds.cargo[3]))
        XCTAssertEqual(ControlIQWeightUnit.kilograms.rawValue, Int(kilograms.cargo[3]))
    }

    func testRoundTripPreservesEveryField() {
        for unit in ControlIQWeightUnit.allCases {
            for enabled in [true, false] {
                let original = ChangeControlIQSettingsRequest(
                    enabled: enabled,
                    weight: 200,
                    weightUnit: unit,
                    totalDailyInsulinUnits: 42,
                    trailingFlag: 1
                )
                let reparsed = ChangeControlIQSettingsRequest(cargo: original.cargo)

                XCTAssertEqual(enabled, reparsed.enabled)
                XCTAssertEqual(200, reparsed.weight)
                XCTAssertEqual(unit, reparsed.weightUnit)
                XCTAssertEqual(42, reparsed.totalDailyInsulinUnits)
                XCTAssertEqual(1, reparsed.trailingFlag)
                XCTAssertEqual(Int(ChangeControlIQSettingsRequest.props.size), original.cargo.count)
            }
        }
    }

    /// Weights above 255 need both weight bytes, so a little-endian regression would
    /// only show up here.
    func testWeightAboveOneByteUsesBothBytes() {
        let request = ChangeControlIQSettingsRequest(
            enabled: true,
            weight: 300,
            weightUnit: .pounds,
            totalDailyInsulinUnits: 60
        )

        XCTAssertEqual(300, ChangeControlIQSettingsRequest(cargo: request.cargo).weight)
        XCTAssertEqual(0x2C, request.cargo[1])
        XCTAssertEqual(0x01, request.cargo[2])
    }

    func testUnknownWeightUnitIsNotGuessed() {
        var cargo = ChangeControlIQSettingsRequest(
            enabled: true,
            weight: 150,
            weightUnit: .pounds,
            totalDailyInsulinUnits: 75
        ).cargo
        cargo[3] = 9

        let parsed = ChangeControlIQSettingsRequest(cargo: cargo)
        XCTAssertEqual(9, parsed.weightUnitRaw)
        XCTAssertNil(parsed.weightUnit)
    }
}

final class ChangeControlIQSettingsResponseTests: XCTestCase {
    func testStatusZeroIsOK() {
        XCTAssertTrue(ChangeControlIQSettingsResponse(status: 0).isStatusOK)
    }

    func testNonZeroStatusIsRejection() {
        let response = ChangeControlIQSettingsResponse(status: 3)
        XCTAssertFalse(response.isStatusOK)
        XCTAssertEqual(3, response.status)
        XCTAssertEqual(3, ChangeControlIQSettingsResponse(cargo: response.cargo).status)
    }
}
