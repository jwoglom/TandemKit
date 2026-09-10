import Foundation

/// Resolves the `endDate` of a finalized bolus.
///
/// The driver notices a bolus is over when it next reads `CurrentBolusStatus`, which is at best
/// ~30 s after the estimated end and at worst a whole sync (~5 min) later — and after a BLE drop
/// mid-bolus, whenever the link comes back. Stamping the detection moment onto `endDate` is what
/// LoopKit then treats as the delivery window: a dose whose window exceeds roughly one 5-minute
/// delta is modelled as continuous delivery across `startDate..endDate`, so an inflated `endDate`
/// smears IOB later than the insulin actually went in (#339).
///
/// Two independent estimates bound the true completion from below, and the later of them is used:
///
/// - **The pump's own timestamp** on the `LastBolusStatus` record. Whether that field is the
///   bolus's start or its completion is not established by any capture we have, which is why it
///   is combined with `max` rather than trusted outright: under the completion reading it is the
///   exact answer, and under the start reading it is `startDate` again and the delivery-rate
///   estimate wins. Either way it can only move `endDate` earlier than detection, never later.
/// - **The delivery-rate estimate**, `startDate + delivered / bolusSpeed`. This is the same model
///   `TandemDoseProgressReporter` reports progress against, applied to the volume the pump says
///   it actually delivered — so a bolus cut short by a cancel gets a proportionally shorter
///   window rather than the full programmed one.
///
/// The result is clamped to `detectedAt`: we never claim delivery finished after the moment we
/// observed it finished, and never at a future date. It is floored at `startDate` so the dose is
/// always well-formed even if the clocks disagree.
enum BolusEndDate {
    // larger total deliveries are faster -- a 10.05u bolus is almost twice as fast as a 9.95u one
    static let bolusSpeedUnder10U = 1 / 28.745858684009523
    static let bolusSpeedOver10U = 1 / 11.200233479381131

    /// How long the pump takes to deliver `units`, at its nominal delivery rate.
    static func estimatedDuration(toBolus units: Double) -> TimeInterval {
        if units < 10 {
            units / bolusSpeedUnder10U
        } else {
            units / bolusSpeedOver10U
        }
    }

    /// - Parameters:
    ///   - startDate: When the bolus was programmed.
    ///   - deliveredUnits: The volume delivered, as the caller resolved it — the pump's reported
    ///     volume, or the programmed one when the pump did not answer. When nil or zero there is
    ///     no rate estimate and only the pump timestamp can move `endDate` off `startDate`.
    ///   - pumpTimestamp: The pump's timestamp on the `LastBolusStatus` record, when one was read.
    ///   - detectedAt: When the driver noticed the bolus had finished.
    static func resolve(
        startDate: Date,
        deliveredUnits: Double?,
        pumpTimestamp: Date?,
        detectedAt: Date = .now
    ) -> Date {
        var candidate = startDate

        if let deliveredUnits, deliveredUnits > 0 {
            candidate = startDate.addingTimeInterval(estimatedDuration(toBolus: deliveredUnits))
        }

        if let pumpTimestamp, pumpTimestamp > candidate {
            candidate = pumpTimestamp
        }

        return max(startDate, min(candidate, detectedAt))
    }
}
