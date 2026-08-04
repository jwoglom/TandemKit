@testable import TandemCore
import XCTest

final class ControlIQSettingsLimitsTests: XCTestCase {
    // MARK: - Unconfigured values

    /// The bug behind issue #223: a pump that never had a weight or TDD entered
    /// reports zero, and enabling Control-IQ with those values is rejected. Catch it
    /// before the write so the user gets told what to fix.
    func testEnablingWithoutWeightIsRejected() {
        XCTAssertThrowsError(
            try ControlIQSettingsLimits.validate(
                enabled: true,
                weight: nil,
                weightUnit: .pounds,
                totalDailyInsulin: 50
            )
        ) { error in
            XCTAssertEqual(ControlIQSettingsError.weightNotConfigured, error as? ControlIQSettingsError)
        }
    }

    func testEnablingWithZeroWeightIsTreatedAsUnconfigured() {
        XCTAssertThrowsError(
            try ControlIQSettingsLimits.validate(
                enabled: true,
                weight: 0,
                weightUnit: .pounds,
                totalDailyInsulin: 50
            )
        ) { error in
            XCTAssertEqual(ControlIQSettingsError.weightNotConfigured, error as? ControlIQSettingsError)
        }
    }

    func testEnablingWithoutTotalDailyInsulinIsRejected() {
        XCTAssertThrowsError(
            try ControlIQSettingsLimits.validate(
                enabled: true,
                weight: 150,
                weightUnit: .pounds,
                totalDailyInsulin: nil
            )
        ) { error in
            XCTAssertEqual(ControlIQSettingsError.totalDailyInsulinNotConfigured, error as? ControlIQSettingsError)
        }
    }

    func testEnablingWithZeroTotalDailyInsulinIsTreatedAsUnconfigured() {
        XCTAssertThrowsError(
            try ControlIQSettingsLimits.validate(
                enabled: true,
                weight: 150,
                weightUnit: .pounds,
                totalDailyInsulin: 0
            )
        ) { error in
            XCTAssertEqual(ControlIQSettingsError.totalDailyInsulinNotConfigured, error as? ControlIQSettingsError)
        }
    }

    // MARK: - Disabling

    /// Turning Control-IQ off must never be blocked by validation, or a user whose
    /// pump has no stored weight could not get back out of Control-IQ from the app.
    func testDisablingIsAllowedWithNoValuesAtAll() {
        XCTAssertNoThrow(
            try ControlIQSettingsLimits.validate(
                enabled: false,
                weight: nil,
                weightUnit: .pounds,
                totalDailyInsulin: nil
            )
        )
    }

    func testDisablingIsAllowedWithOutOfRangeValues() {
        XCTAssertNoThrow(
            try ControlIQSettingsLimits.validate(
                enabled: false,
                weight: 1,
                weightUnit: .pounds,
                totalDailyInsulin: 1
            )
        )
    }

    // MARK: - Ranges

    func testWeightRangeIsUnitAware() {
        XCTAssertEqual(
            ControlIQSettingsLimits.minimumWeightPounds,
            ControlIQSettingsLimits.weightRange(for: .pounds).lowerBound
        )
        XCTAssertEqual(
            ControlIQSettingsLimits.minimumWeightKilograms,
            ControlIQSettingsLimits.weightRange(for: .kilograms).lowerBound
        )
        XCTAssertLessThan(
            ControlIQSettingsLimits.weightRange(for: .kilograms).upperBound,
            ControlIQSettingsLimits.weightRange(for: .pounds).upperBound
        )
    }

    /// A weight that is fine in pounds is below the minimum in kilograms, which is
    /// exactly the mix-up an ignored weight unit produces.
    func testWeightValidAsPoundsIsRejectedAsKilograms() {
        XCTAssertNoThrow(
            try ControlIQSettingsLimits.validate(
                enabled: true,
                weight: 150,
                weightUnit: .pounds,
                totalDailyInsulin: 50
            )
        )

        XCTAssertThrowsError(
            try ControlIQSettingsLimits.validate(
                enabled: true,
                weight: 20,
                weightUnit: .kilograms,
                totalDailyInsulin: 50
            )
        )
    }

    func testWeightBelowMinimumIsRejected() {
        XCTAssertThrowsError(
            try ControlIQSettingsLimits.validate(
                enabled: true,
                weight: ControlIQSettingsLimits.minimumWeightPounds - 1,
                weightUnit: .pounds,
                totalDailyInsulin: 50
            )
        ) { error in
            guard let settingsError = error as? ControlIQSettingsError,
                  case .weightOutOfRange = settingsError
            else {
                return XCTFail("Expected weightOutOfRange, got \(error)")
            }
        }
    }

    func testTotalDailyInsulinBelowMinimumIsRejected() {
        XCTAssertThrowsError(
            try ControlIQSettingsLimits.validate(
                enabled: true,
                weight: 150,
                weightUnit: .pounds,
                totalDailyInsulin: ControlIQSettingsLimits.minimumTotalDailyInsulinUnits - 1
            )
        ) { error in
            guard let settingsError = error as? ControlIQSettingsError,
                  case .totalDailyInsulinOutOfRange = settingsError
            else {
                return XCTFail("Expected totalDailyInsulinOutOfRange, got \(error)")
            }
        }
    }

    func testValuesAtTheBoundsAreAccepted() {
        for unit in ControlIQWeightUnit.allCases {
            let weights = ControlIQSettingsLimits.weightRange(for: unit)
            for weight in [weights.lowerBound, weights.upperBound] {
                XCTAssertNoThrow(
                    try ControlIQSettingsLimits.validate(
                        enabled: true,
                        weight: weight,
                        weightUnit: unit,
                        totalDailyInsulin: ControlIQSettingsLimits.minimumTotalDailyInsulinUnits
                    ),
                    "\(weight) \(unit) should be accepted"
                )
            }
        }

        let tdi = ControlIQSettingsLimits.totalDailyInsulinRange
        for units in [tdi.lowerBound, tdi.upperBound] {
            XCTAssertNoThrow(
                try ControlIQSettingsLimits.validate(
                    enabled: true,
                    weight: 150,
                    weightUnit: .pounds,
                    totalDailyInsulin: units
                ),
                "\(units) U should be accepted"
            )
        }
    }

    // MARK: - Messages

    /// Every rejection has to be able to explain itself; "check pump connection" is
    /// what this replaces.
    func testEveryErrorHasADescription() {
        let errors: [ControlIQSettingsError] = [
            .weightNotConfigured,
            .totalDailyInsulinNotConfigured,
            .weightOutOfRange(weight: 10, unit: .pounds, allowed: 55 ... 400),
            .totalDailyInsulinOutOfRange(units: 1, allowed: 10 ... 200),
            .rejectedByPump(status: 3),
            .unknownWeightUnit(raw: 9)
        ]

        for error in errors {
            let description = error.errorDescription
            XCTAssertNotNil(description, "\(error) has no description")
            XCTAssertFalse(description?.isEmpty ?? true, "\(error) has an empty description")
        }
    }

    func testPumpRejectionReportsTheRawStatus() {
        let description = ControlIQSettingsError.rejectedByPump(status: 7).errorDescription
        XCTAssertEqual(true, description?.contains("7"))
    }
}

final class ControlIQWeightUnitTests: XCTestCase {
    func testRawValuesMatchTheWireFormat() {
        XCTAssertEqual(0, ControlIQWeightUnit.kilograms.rawValue)
        XCTAssertEqual(1, ControlIQWeightUnit.pounds.rawValue)
    }

    func testConversionRoundTrips() {
        for kilograms in [25, 68, 100, 181] {
            let pounds = ControlIQWeightUnit.kilograms.convert(kilograms, to: .pounds)
            XCTAssertEqual(
                kilograms,
                ControlIQWeightUnit.pounds.convert(pounds, to: .kilograms),
                "\(kilograms) kg did not round-trip"
            )
        }
    }

    func testConversionToTheSameUnitIsIdentity() {
        XCTAssertEqual(150, ControlIQWeightUnit.pounds.convert(150, to: .pounds))
        XCTAssertEqual(68, ControlIQWeightUnit.kilograms.convert(68, to: .kilograms))
    }

    func testKnownConversion() {
        XCTAssertEqual(150, ControlIQWeightUnit.kilograms.convert(68, to: .pounds))
        XCTAssertEqual(68, ControlIQWeightUnit.pounds.convert(150, to: .kilograms))
    }
}
