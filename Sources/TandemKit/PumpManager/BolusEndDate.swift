import Foundation

/// Resolves the delivery window of a finalized bolus.
///
/// The driver only notices a bolus is over when it next reads `CurrentBolusStatus` — at best ~30 s
/// late, at worst a sync (~5 min) later, and after a mid-bolus BLE drop whenever the link comes
/// back. LoopKit models a dose whose window exceeds roughly one 5-minute delta as continuous
/// delivery across `startDate..endDate`, so dating the end at detection smears IOB later than the
/// insulin went in (#339).
///
/// The pump's own timestamps are used instead, with the delivery-rate model as a fallback:
///
/// - `CurrentBolusStatus.timestamp` in the delivering state is when delivery began — exactly
///   `TandemPumpCapabilities.bolusInitiationDelay` after the pump accepts the request.
///   `UnfinalizedDose` records it.
/// - `LastBolusStatus.timestamp` is when delivery ended. Verified against 114 boluses in three
///   days of Mobi logs: that timestamp minus the delivery-start one equalled delivered volume over
///   the rate below to within -1.6…+1.1 s, across 3 s to 178 s of delivery. Both fields stamp the
///   pump event, not the reply — repeat reads of one unchanged state come back identical.
/// - The rate estimate, `deliveryStart + delivered / bolusSpeed`, is the fallback when there is no
///   usable pump timestamp, and the floor under one that is older than the delivery can have been.
///   Both the rate and the lead-in are `TandemPumpCapabilities` constants.
///
/// Callers translate pump timestamps onto the host clock before resolving. The result is clamped
/// to `detectedAt` and floored at the dose's start as a final guard against measurement error.
enum BolusEndDate {
    /// - Parameters:
    ///   - startDate: When the driver programmed the bolus.
    ///   - deliveryStartDate: When the pump said delivery began, when that was seen. Without it,
    ///     delivery is assumed to have begun `bolusInitiationDelay` after `startDate`.
    ///   - deliveredUnits: The volume delivered, as the caller resolved it — the pump's reported
    ///     volume, or the programmed one when the pump did not answer.
    ///   - pumpTimestamp: The pump's timestamp on the `LastBolusStatus` record, when one was read.
    ///   - detectedAt: When the driver noticed the bolus had finished.
    static func resolve(
        startDate: Date,
        deliveryStartDate: Date? = nil,
        deliveredUnits: Double?,
        pumpTimestamp: Date?,
        detectedAt: Date = .now
    ) -> Date {
        let deliveryStart = deliveryStartDate
            ?? startDate.addingTimeInterval(TandemPumpCapabilities.bolusInitiationDelay)
        var candidate = deliveryStart

        if let deliveredUnits, deliveredUnits > 0 {
            candidate = deliveryStart
                .addingTimeInterval(TandemPumpCapabilities.estimatedBolusDuration(toDeliver: deliveredUnits))
        }

        if let pumpTimestamp, pumpTimestamp > candidate {
            candidate = pumpTimestamp
        }

        let doseStart = deliveryStartDate ?? startDate
        return max(doseStart, min(candidate, detectedAt))
    }
}
