import LoopKit
@testable import TandemKit
import XCTest

/// The `.basal` marker reports a rate the pump is already running, so it is rounded to the nearest
/// rate the pump can express rather than floored — flooring reported a 0.05 U/hr segment as no
/// basal at all (#335).
final class BasalMarkerRateRoundingTests: XCTestCase {
    private func reportedRate(for rate: Double) -> Double {
        UnfinalizedDose(basalRate: rate, insulinType: nil).toDoseEntry().unitsPerHour
    }

    func testARateBelowThePumpMinimumReportsTheMinimumNotZero() {
        XCTAssertEqual(reportedRate(for: 0.05), 0.1, accuracy: 1e-9)
        XCTAssertEqual(reportedRate(for: 0.09), 0.1, accuracy: 1e-9)
    }

    /// Below half the minimum there is genuinely nothing closer than zero.
    func testARateNearZeroStillReportsZero() {
        XCTAssertEqual(reportedRate(for: 0), 0)
        XCTAssertEqual(reportedRate(for: 0.004), 0)
    }

    func testAnOffGridRateReportsTheNearestSupportedRate() {
        XCTAssertEqual(reportedRate(for: 1.2349), 1.23, accuracy: 1e-9)
        XCTAssertEqual(reportedRate(for: 1.2351), 1.24, accuracy: 1e-9)
    }

    func testARateOnTheGridIsUnchanged() {
        for rate in [0.1, 0.55, 1.0, 3.33, 15.0] {
            XCTAssertEqual(reportedRate(for: rate), rate, accuracy: 1e-9, "\(rate)")
        }
    }

    func testARateAboveThePumpMaximumReportsTheMaximum() {
        XCTAssertEqual(reportedRate(for: 20.0), 15.0, accuracy: 1e-9)
    }

    /// Whatever the input, the reported rate is never further than half a grid step away.
    func testTheReportedRateIsNeverMoreThanHalfAGridStepOff() {
        for thousandths in stride(from: 0, through: 15000, by: 7) {
            let rate = Double(thousandths) / 1000
            XCTAssertLessThanOrEqual(abs(reportedRate(for: rate) - rate), 0.05 + 1e-9, "\(rate)")
        }
    }
}
