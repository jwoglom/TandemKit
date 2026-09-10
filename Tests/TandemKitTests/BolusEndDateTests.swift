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
    /// the volume it reports having delivered — starting from when delivery began, not from when
    /// the bolus was programmed.
    func testRateEstimateDatesTheEndFromTheDeliveredVolume() {
        let end = BolusEndDate.resolve(
            startDate: start,
            deliveryStartDate: start.addingTimeInterval(15),
            deliveredUnits: 2.0,
            pumpTimestamp: nil,
            detectedAt: start.addingTimeInterval(600)
        )

        XCTAssertEqual(
            end.timeIntervalSince(start),
            15 + TandemPumpCapabilities.estimatedBolusDuration(toDeliver: 2.0),
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

    /// Without the pump's delivery start, the lead-in is assumed: the pump spends 15 s accepting
    /// the request before any insulin moves.
    func testTheLeadInIsAssumedWhenTheDeliveryStartWasNotSeen() {
        let end = BolusEndDate.resolve(
            startDate: start,
            deliveredUnits: 2.0,
            pumpTimestamp: nil,
            detectedAt: start.addingTimeInterval(600)
        )

        XCTAssertEqual(
            end.timeIntervalSince(start),
            TandemPumpCapabilities.bolusInitiationDelay + TandemPumpCapabilities.estimatedBolusDuration(toDeliver: 2.0),
            accuracy: 1e-6
        )
    }

    /// Nothing to estimate from: the dose collapses to an instant at the start of delivery rather
    /// than stretching to the detection moment.
    func testNoDeliveryAndNoTimestampCollapsesToTheStartOfDelivery() {
        let deliveryStart = start.addingTimeInterval(15)
        XCTAssertEqual(
            BolusEndDate.resolve(
                startDate: start,
                deliveryStartDate: deliveryStart,
                deliveredUnits: 0,
                pumpTimestamp: nil,
                detectedAt: start.addingTimeInterval(600)
            ),
            deliveryStart
        )
        XCTAssertEqual(
            BolusEndDate.resolve(
                startDate: start,
                deliveryStartDate: deliveryStart,
                deliveredUnits: nil,
                pumpTimestamp: nil,
                detectedAt: start.addingTimeInterval(600)
            ),
            deliveryStart
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

    /// The shape the hardware logs actually show: the pump accepts the request, starts delivering
    /// 15 s later, and stamps the end at start-of-delivery + volume / rate. The pump's stamp is
    /// therefore *later* than the rate estimate taken from `startDate`, and has to win — it is the
    /// measurement, and the estimate only ever misses the 15 s of lead-in.
    func testPumpTimestampWinsOverAnEstimateThatOmitsTheDeliveryLeadIn() {
        let deliveryStartedAt = start.addingTimeInterval(TandemPumpCapabilities.bolusInitiationDelay)
        let pumpEnd = deliveryStartedAt.addingTimeInterval(TandemPumpCapabilities.estimatedBolusDuration(toDeliver: 2.0) + 4)

        let end = BolusEndDate.resolve(
            startDate: start,
            deliveredUnits: 2.0,
            pumpTimestamp: pumpEnd,
            detectedAt: start.addingTimeInterval(300)
        )

        XCTAssertEqual(end, pumpEnd)
    }

    /// The pump's timestamp is the end of delivery (verified on hardware, see `BolusEndDate`),
    /// so a record that predates what the delivered volume alone must have taken is not one that
    /// can describe this bolus — a stale record, or a pump clock behind the phone's. The rate
    /// estimate is the floor under it rather than being discarded for it.
    func testATimestampEarlierThanTheDeliveryTookIsFlooredByTheRateEstimate() {
        let end = BolusEndDate.resolve(
            startDate: start,
            deliveryStartDate: start.addingTimeInterval(15),
            deliveredUnits: 2.0,
            pumpTimestamp: start.addingTimeInterval(20),
            detectedAt: start.addingTimeInterval(600)
        )

        XCTAssertEqual(
            end.timeIntervalSince(start),
            15 + TandemPumpCapabilities.estimatedBolusDuration(toDeliver: 2.0),
            // Date arithmetic near the 2023 epoch has ~1e-7 s of float resolution.
            accuracy: 1e-6
        )
    }

    /// A pump clock running behind the phone's cannot drag the end before delivery began.
    func testTimestampBeforeTheStartIsIgnored() {
        let deliveryStart = start.addingTimeInterval(15)
        let end = BolusEndDate.resolve(
            startDate: start,
            deliveryStartDate: deliveryStart,
            deliveredUnits: 0,
            pumpTimestamp: start.addingTimeInterval(-3600),
            detectedAt: start.addingTimeInterval(600)
        )

        XCTAssertEqual(end, deliveryStart)
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
            deliveryStartDate: nil,
            deliveredUnits: 1.0,
            pumpTimestamp: start.addingTimeInterval(30),
            detectedAt: start.addingTimeInterval(-60)
        )

        XCTAssertEqual(end, start)
    }

}

/// `UnfinalizedDose` carries the pump's start of delivery, which is what the reported dose starts
/// at while `startDate` stays the dose's identity.
final class UnfinalizedDoseDeliveryStartTests: XCTestCase {
    private func bolus(units: Double = 2.0) -> UnfinalizedDose {
        UnfinalizedDose(
            units: units,
            duration: TandemPumpCapabilities.estimatedBolusDuration(toDeliver: units),
            activationType: .manualNoRecommendation,
            insulinType: nil,
            bolusId: 42
        )
    }

    func testDeliveryStartIsWhatTheDoseStartsAt() {
        let dose = bolus()
        let deliveryStart = dose.startDate.addingTimeInterval(15)

        XCTAssertEqual(dose.doseStartDate, dose.startDate)
        XCTAssertEqual(dose.toDoseEntry().startDate, dose.startDate)

        dose.recordDeliveryStart(deliveryStart, now: deliveryStart.addingTimeInterval(60))

        XCTAssertEqual(dose.doseStartDate, deliveryStart)
        XCTAssertEqual(dose.toDoseEntry().startDate, deliveryStart)
        XCTAssertEqual(dose.startDate, dose.startDate)
    }

    /// The pump clock runs a few seconds off ours in either direction, and neither answer is
    /// usable: delivery did not begin before we programmed the bolus, or in the future.
    func testDeliveryStartIsClampedToTheProgrammedStartAndNow() {
        let early = bolus()
        early.recordDeliveryStart(early.startDate.addingTimeInterval(-30), now: early.startDate.addingTimeInterval(60))
        XCTAssertEqual(early.deliveryStartDate, early.startDate)

        let late = bolus()
        let now = late.startDate.addingTimeInterval(20)
        late.recordDeliveryStart(now.addingTimeInterval(3600), now: now)
        XCTAssertEqual(late.deliveryStartDate, now)
    }

    /// Persisted, so a bolus that outlives an app restart is still reported over the right window.
    func testDeliveryStartSurvivesRawValueRoundTrip() throws {
        let dose = bolus()
        let deliveryStart = dose.startDate.addingTimeInterval(15)
        dose.recordDeliveryStart(deliveryStart, now: deliveryStart.addingTimeInterval(60))

        let restored = try XCTUnwrap(UnfinalizedDose(rawValue: dose.rawValue))

        XCTAssertEqual(restored.deliveryStartDate, deliveryStart)
        XCTAssertEqual(restored.startDate, dose.startDate)
    }
}
