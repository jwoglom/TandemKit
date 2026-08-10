@testable import TandemKit
import XCTest

final class ControlIQSettingsLimitsTests: XCTestCase {
    // MARK: - Validation

    /// Zero is what a pump reports when Control-IQ has never been configured on it, and it is the
    /// value that made enabling Control-IQ fail with no usable explanation (#223).
    func testZeroWeightIsRejected() {
        XCTAssertEqual(
            ControlIQSettingsLimits.validate(weightLbs: 0, totalDailyInsulinUnits: 30),
            .weightOutOfRange(lbs: 0)
        )
    }

    func testZeroTotalDailyInsulinIsRejected() {
        XCTAssertEqual(
            ControlIQSettingsLimits.validate(weightLbs: 150, totalDailyInsulinUnits: 0),
            .totalDailyInsulinOutOfRange(units: 0)
        )
    }

    /// Weight is reported first, so a request missing both values names the weight.
    func testWeightIsReportedBeforeTotalDailyInsulin() {
        XCTAssertEqual(
            ControlIQSettingsLimits.validate(weightLbs: 0, totalDailyInsulinUnits: 0),
            .weightOutOfRange(lbs: 0)
        )
    }

    func testAnyNonzeroWeightIsAccepted() {
        XCTAssertNil(ControlIQSettingsLimits.validate(weightLbs: 1, totalDailyInsulinUnits: 10))
        XCTAssertNil(ControlIQSettingsLimits.validate(weightLbs: 400, totalDailyInsulinUnits: 10))
    }

    /// Control-IQ requires at least 10 U/day.
    func testTotalDailyInsulinBelowTenIsRejected() {
        XCTAssertEqual(
            ControlIQSettingsLimits.validate(weightLbs: 150, totalDailyInsulinUnits: 9),
            .totalDailyInsulinOutOfRange(units: 9)
        )
        XCTAssertNil(ControlIQSettingsLimits.validate(weightLbs: 150, totalDailyInsulinUnits: 10))
    }

    /// Both fields are bounded by the wire format: two bytes for the weight, one for the TDI.
    func testValuesTooWideForTheWireAreRejected() {
        XCTAssertEqual(
            ControlIQSettingsLimits.validate(weightLbs: 0x1_0000, totalDailyInsulinUnits: 30),
            .weightOutOfRange(lbs: 0x1_0000)
        )
        XCTAssertEqual(
            ControlIQSettingsLimits.validate(weightLbs: 150, totalDailyInsulinUnits: 256),
            .totalDailyInsulinOutOfRange(units: 256)
        )
    }

    // MARK: - Weight unit conversion

    /// The request always declares pounds, so a pump displaying kilograms has to be converted --
    /// echoing its reading back unchanged would turn 70 kg into 70 lb.
    func testKilogramsAreConvertedToPounds() {
        XCTAssertEqual(ControlIQSettingsLimits.pounds(from: 70, unit: .kilograms), 154)
        XCTAssertEqual(ControlIQSettingsLimits.pounds(from: 25, unit: .kilograms), 55)
        XCTAssertEqual(ControlIQSettingsLimits.pounds(from: 1, unit: .kilograms), 2)
    }

    func testPoundsArePassedThrough() {
        XCTAssertEqual(ControlIQSettingsLimits.pounds(from: 154, unit: .pounds), 154)
    }

    /// An unrecognized unit id is treated as pounds, matching what the request carries.
    func testUnknownUnitIsTreatedAsPounds() {
        XCTAssertEqual(ControlIQSettingsLimits.pounds(from: 154, unit: nil), 154)
    }

    /// Zero means "not configured" in either unit, and must not become a nonzero weight.
    func testZeroConvertsToZero() {
        XCTAssertEqual(ControlIQSettingsLimits.pounds(from: 0, unit: .kilograms), 0)
        XCTAssertEqual(ControlIQSettingsLimits.pounds(from: 0, unit: .pounds), 0)
    }
}
