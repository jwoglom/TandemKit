@testable import TandemKit
import XCTest

/// The finalized `endDate` of a bolus used to be the moment the driver noticed the bolus was
/// over, which is at best ~30 s late and after a reconnect can be minutes late (#339). LoopKit
/// models a dose whose window is longer than one ~5-minute delta as continuous delivery, so that
/// inflated window smears IOB later than the insulin actually went in. These pin the replacement.
final class BolusEndDateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Delivery-rate estimate

    /// With no pump timestamp, the window is what the pump's delivery rate says it took to push
    /// the volume it reports having delivered.
    func testRateEstimateDatesTheEndFromTheDeliveredVolume() {
        let end = BolusEndDate.resolve(
            startDate: start,
            deliveredUnits: 2.0,
            pumpTimestamp: nil,
            detectedAt: start.addingTimeInterval(600)
        )

        XCTAssertEqual(
            end.timeIntervalSince(start),
            BolusEndDate.estimatedDuration(toBolus: 2.0),
            // Date arithmetic near the 2023 epoch has ~1e-7 s of float resolution.
            accuracy: 1e-6
        )
    }

    /// A bolus cut short gets a proportionally shorter window, not the programmed one.
    func testPartialDeliveryGivesAShorterWindowThanAFullOne() {
        let partial = BolusEndDate.resolve(
            startDate: start,
            deliveredUnits: 0.5,
            pumpTimestamp: nil,
            detectedAt: start.addingTimeInterval(600)
        )
        let full = BolusEndDate.resolve(
            startDate: start,
            deliveredUnits: 5.0,
            pumpTimestamp: nil,
            detectedAt: start.addingTimeInterval(600)
        )

        XCTAssertLessThan(partial, full)
    }

    /// Nothing to estimate from: the dose collapses to an instant at its start rather than
    /// stretching to the detection moment.
    func testNoDeliveryAndNoTimestampCollapsesToTheStart() {
        XCTAssertEqual(
            BolusEndDate.resolve(
                startDate: start,
                deliveredUnits: 0,
                pumpTimestamp: nil,
                detectedAt: start.addingTimeInterval(600)
            ),
            start
        )
        XCTAssertEqual(
            BolusEndDate.resolve(
                startDate: start,
                deliveredUnits: nil,
                pumpTimestamp: nil,
                detectedAt: start.addingTimeInterval(600)
            ),
            start
        )
    }

    // MARK: - Pump timestamp

    /// The whole point of the fix: a completion the driver only noticed five minutes late is
    /// dated by the pump, not by the detection.
    func testPumpTimestampWinsOverALateDetection() {
        let pumpEnd = start.addingTimeInterval(60)
        let detectedAt = start.addingTimeInterval(300)

        let end = BolusEndDate.resolve(
            startDate: start,
            deliveredUnits: 1.0,
            pumpTimestamp: pumpEnd,
            detectedAt: detectedAt
        )

        XCTAssertEqual(end, pumpEnd)
        XCTAssertLessThan(end, detectedAt)
    }

    /// Whether the pump's field is the bolus's start or its completion is not established by any
    /// capture. Under the start reading it lands on `startDate`, and the rate estimate — never
    /// discarded, only maxed against — still dates the end.
    func testAStartLikeTimestampFallsBackToTheRateEstimate() {
        let end = BolusEndDate.resolve(
            startDate: start,
            deliveredUnits: 2.0,
            pumpTimestamp: start,
            detectedAt: start.addingTimeInterval(600)
        )

        XCTAssertEqual(
            end.timeIntervalSince(start),
            BolusEndDate.estimatedDuration(toBolus: 2.0),
            // Date arithmetic near the 2023 epoch has ~1e-7 s of float resolution.
            accuracy: 1e-6
        )
    }

    /// A pump clock running behind the phone's cannot drag the end before the bolus began.
    func testTimestampBeforeTheStartIsIgnored() {
        let end = BolusEndDate.resolve(
            startDate: start,
            deliveredUnits: 0,
            pumpTimestamp: start.addingTimeInterval(-3600),
            detectedAt: start.addingTimeInterval(600)
        )

        XCTAssertEqual(end, start)
    }

    /// A pump clock running ahead cannot put delivery in the future, or after we saw it end.
    func testTimestampAfterDetectionIsClampedToDetection() {
        let detectedAt = start.addingTimeInterval(120)

        let end = BolusEndDate.resolve(
            startDate: start,
            deliveredUnits: 1.0,
            pumpTimestamp: start.addingTimeInterval(4000),
            detectedAt: detectedAt
        )

        XCTAssertEqual(end, detectedAt)
    }

    /// A delivery still nominally in progress when we noticed it ended is clamped too: the rate
    /// estimate is a model, and detection is an observation.
    func testRateEstimateIsClampedToDetection() {
        let detectedAt = start.addingTimeInterval(5)

        let end = BolusEndDate.resolve(
            startDate: start,
            deliveredUnits: 5.0,
            pumpTimestamp: nil,
            detectedAt: detectedAt
        )

        XCTAssertEqual(end, detectedAt)
    }

    /// Degenerate clocks must still produce a well-formed dose: endDate >= startDate.
    func testEndIsNeverBeforeTheStart() {
        let end = BolusEndDate.resolve(
            startDate: start,
            deliveredUnits: 1.0,
            pumpTimestamp: start.addingTimeInterval(30),
            detectedAt: start.addingTimeInterval(-60)
        )

        XCTAssertEqual(end, start)
    }

    // MARK: - Delivery rate

    /// Deliveries of 10 U and over run at the faster rate, so the threshold has to be pinned:
    /// a 10 U bolus must not be dated with the slow rate's ~5-minute window.
    func testDeliveryRateSwitchesAtTenUnits() {
        XCTAssertEqual(BolusEndDate.estimatedDuration(toBolus: 1.0), 28.745858684009523, accuracy: 1e-9)
        XCTAssertEqual(BolusEndDate.estimatedDuration(toBolus: 10.0), 112.00233479381131, accuracy: 1e-9)
        XCTAssertLessThan(
            BolusEndDate.estimatedDuration(toBolus: 10.0),
            BolusEndDate.estimatedDuration(toBolus: 9.99)
        )
    }
}
