@testable import TandemCore
import XCTest

/// A pump that has never had a Control-IQ weight or total daily insulin entered
/// reports zero for both. Zero is not a weight and not a dose — it means "not
/// configured", and treating it as data is what made enabling Control-IQ fail with
/// nothing but a pump status byte to show for it (issue #223).
final class ControlIQInfoConfiguredValuesTests: XCTestCase {
    private func makeV2(weight: Int, totalDailyInsulin: Int, weightUnit: Int = 1) -> ControlIQInfoV2Response {
        ControlIQInfoV2Response(
            closedLoopEnabled: false,
            weight: weight,
            weightUnit: weightUnit,
            totalDailyInsulin: totalDailyInsulin,
            currentUserModeType: 0,
            byte6: 0,
            byte7: 0,
            byte8: 0,
            controlStateType: 0,
            exerciseChoice: 0,
            exerciseDuration: 0,
            exerciseTimeRemaining: 0
        )
    }

    private func makeV1(weight: Int, totalDailyInsulin: Int, weightUnit: Int = 1) -> ControlIQInfoV1Response {
        ControlIQInfoV1Response(
            closedLoopEnabled: false,
            weight: weight,
            weightUnit: weightUnit,
            totalDailyInsulin: totalDailyInsulin,
            currentUserModeType: 0,
            byte6: 0,
            byte7: 0,
            byte8: 0,
            controlStateType: 0
        )
    }

    func testZeroWeightIsReportedAsUnconfigured() {
        let response = makeV2(weight: 0, totalDailyInsulin: 50)

        XCTAssertFalse(response.isWeightConfigured)
        XCTAssertNil(response.configuredWeight)
        XCTAssertTrue(response.isTotalDailyInsulinConfigured)
        XCTAssertEqual(50, response.configuredTotalDailyInsulin)
    }

    func testZeroTotalDailyInsulinIsReportedAsUnconfigured() {
        let response = makeV2(weight: 150, totalDailyInsulin: 0)

        XCTAssertTrue(response.isWeightConfigured)
        XCTAssertEqual(150, response.configuredWeight)
        XCTAssertFalse(response.isTotalDailyInsulinConfigured)
        XCTAssertNil(response.configuredTotalDailyInsulin)
    }

    /// The state the issue reporter was in: a brand-new Control-IQ setup with neither
    /// value stored on the pump.
    func testFreshPumpReportsNeitherValue() {
        let response = makeV2(weight: 0, totalDailyInsulin: 0)

        XCTAssertNil(response.configuredWeight)
        XCTAssertNil(response.configuredTotalDailyInsulin)
    }

    func testConfiguredValuesArePassedThrough() {
        let response = makeV2(weight: 150, totalDailyInsulin: 50)

        XCTAssertEqual(150, response.configuredWeight)
        XCTAssertEqual(50, response.configuredTotalDailyInsulin)
    }

    func testV1ResponseBehavesTheSameWay() {
        XCTAssertNil(makeV1(weight: 0, totalDailyInsulin: 0).configuredWeight)
        XCTAssertNil(makeV1(weight: 0, totalDailyInsulin: 0).configuredTotalDailyInsulin)
        XCTAssertEqual(150, makeV1(weight: 150, totalDailyInsulin: 50).configuredWeight)
        XCTAssertEqual(50, makeV1(weight: 150, totalDailyInsulin: 50).configuredTotalDailyInsulin)
    }

    // MARK: - Weight unit

    func testWeightUnitIsDecoded() {
        XCTAssertEqual(.pounds, makeV2(weight: 150, totalDailyInsulin: 50, weightUnit: 1).weightUnit)
        XCTAssertEqual(.kilograms, makeV2(weight: 68, totalDailyInsulin: 50, weightUnit: 0).weightUnit)
    }

    /// An unrecognized unit must stay `nil` rather than defaulting to pounds: writing
    /// a kilogram weight back as pounds would change the user's stored weight.
    func testUnknownWeightUnitIsNil() {
        XCTAssertNil(makeV2(weight: 150, totalDailyInsulin: 50, weightUnit: 9).weightUnit)
    }

    /// The unit the pump reports has to be the one we can write back, so the read and
    /// write paths must share a single type.
    func testResponseWeightUnitIsTheSameTypeTheRequestTakes() {
        guard let unit = makeV2(weight: 68, totalDailyInsulin: 50, weightUnit: 0).weightUnit else {
            return XCTFail("Expected a decoded weight unit")
        }

        let request = ChangeControlIQSettingsRequest(
            enabled: true,
            weight: 68,
            weightUnit: unit,
            totalDailyInsulinUnits: 50
        )

        XCTAssertEqual(ControlIQWeightUnit.kilograms, request.weightUnit)
        XCTAssertEqual(0, Int(request.cargo[3]))
    }
}
