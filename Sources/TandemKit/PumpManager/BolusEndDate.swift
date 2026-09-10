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
/// The pump's own record is the answer, with the delivery-rate model as a floor under it:
///
/// - **`LastBolusStatus.timestamp` is the moment delivery ended.** Verified against 114 boluses
///   over three days of driver logs from a Mobi (V2 responses): for every one of them, that
///   timestamp minus the delivery-start timestamp the pump reports on `CurrentBolusStatus`
///   (`statusId == delivering`) equalled the delivered volume divided by the nominal delivery
///   rate below, with a residual of -1.6 s to +1.1 s (mean -0.5 s, consistent with the field
///   being truncated to whole seconds) across durations from 3 s to 178 s. A start timestamp
///   could not scale with the volume like that. It stamps the event rather than the reply, in
///   the same way `CurrentBolusStatus.timestamp` does — repeat reads of one unchanged pump state
///   seconds apart come back with an identical timestamp.
/// - **The delivery-rate estimate**, `startDate + delivered / bolusSpeed`. This is the same model
///   `TandemDoseProgressReporter` reports progress against, applied to the volume the pump says
///   it actually delivered — so a bolus cut short by a cancel gets a proportionally shorter
///   window rather than the full programmed one. Taking the later of the two (`max`) keeps the
///   window from collapsing toward `startDate` when the pump timestamp is missing, zero, or
///   describes a bolus that ended earlier than ours could have.
///
/// The result is clamped to `detectedAt`: we never claim delivery finished after the moment we
/// observed it finished, and never at a future date. That clamp is load-bearing, because the two
/// clocks are not the same clock — in those same logs the pump ran about 7-8 s ahead of the phone
/// (-3 s to +10 s across the captures), so a promptly detected bolus would otherwise be dated a
/// few seconds into the future. Being wrong by that much is the point of the trade: it replaces
/// an error measured in minutes. The result is also floored at `startDate` so the dose stays
/// well-formed whichever way the clocks disagree.
///
/// Note the same captures show delivery starting exactly 15 s after the pump accepts the request,
/// so `startDate` (when the driver programmed the bolus) is about that much earlier than when
/// insulin first moved. `CurrentBolusStatus.timestamp` in the `delivering` state is the pump's own
/// start of delivery and would fix that; it is not used here, since #339 is about `endDate`.
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
    ///   - pumpTimestamp: The pump's timestamp on the `LastBolusStatus` record — the moment
    ///     delivery ended — when one was read.
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
