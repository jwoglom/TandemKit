import LoopKit
@testable import TandemKit
import XCTest

/// A temp basal's `deliveredUnits` is computed from the programmed rate and the time it ran — the
/// pump reports no measured volume for one — so it has to land on the pump's own 0.001 U
/// accounting grid and can never go negative (#335).
final class UnfinalizedDoseTempBasalDeliveryTests: XCTestCase {
    private func tempBasal(rate: Double, duration: TimeInterval) -> UnfinalizedDose {
        UnfinalizedDose(tempRate: rate, duration: duration, automatic: true, insulinType: nil)
    }

    func testDeliveredUnitsAreRoundedToThePumpsResolution() throws {
        // 1.35 U/h for 29 minutes is 0.6525 U, which the pump accounts as 0.653.
        let dose = tempBasal(rate: 1.35, duration: .minutes(30))

        let entry = dose.toDoseEntry(endDate: dose.startDate.addingTimeInterval(.minutes(29)))

        XCTAssertEqual(try XCTUnwrap(entry.deliveredUnits), 0.653, accuracy: 1e-12)
    }

    /// Rounding must not cost anything on a volume that already lands on the grid.
    func testAnExactVolumeIsUnchanged() throws {
        let dose = tempBasal(rate: 2.0, duration: .minutes(30))

        let entry = dose.toDoseEntry(endDate: dose.estimatedEndDate)

        XCTAssertEqual(try XCTUnwrap(entry.deliveredUnits), 1.0, accuracy: 1e-12)
    }

    func testDeliveredUnitsHaveNoMoreThanThreeDecimals() throws {
        for minutes in stride(from: 1.0, through: 180.0, by: 1.0) {
            let dose = tempBasal(rate: 1.35, duration: .hours(4))
            let entry = dose.toDoseEntry(endDate: dose.startDate.addingTimeInterval(.minutes(minutes)))
            let delivered = try XCTUnwrap(entry.deliveredUnits)

            XCTAssertEqual(delivered * 1000, (delivered * 1000).rounded(), accuracy: 1e-6, "\(minutes)min")
        }
    }

    /// An end before the start (a backwards clock step, or a stop time resolved too early) must not
    /// report negative insulin.
    func testAnEndBeforeTheStartDeliversNothing() throws {
        let dose = tempBasal(rate: 2.0, duration: .minutes(30))

        let entry = dose.toDoseEntry(endDate: dose.startDate.addingTimeInterval(-.minutes(10)))

        XCTAssertEqual(try XCTUnwrap(entry.deliveredUnits), 0)
    }

    /// Natural expiry stays clamped to the programmed end: a sync that notices late must not bill
    /// insulin for time after the temp rate was over.
    func testDeliveryStopsAtTheProgrammedEnd() throws {
        let dose = tempBasal(rate: 2.0, duration: .minutes(30))

        let entry = dose.toDoseEntry(endDate: dose.estimatedEndDate.addingTimeInterval(.minutes(10)))

        XCTAssertEqual(entry.endDate, dose.estimatedEndDate)
        XCTAssertEqual(try XCTUnwrap(entry.deliveredUnits), 1.0, accuracy: 1e-12)
    }

    /// A running temp basal reports no delivered volume at all.
    func testAMutableTempBasalReportsNoDeliveredUnits() {
        let dose = tempBasal(rate: 2.0, duration: .minutes(30))

        XCTAssertNil(dose.toDoseEntry(isMutable: true).deliveredUnits)
    }
}
