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
///   `bolusInitiationDelay` after the pump accepts the request. `UnfinalizedDose` records it.
/// - `LastBolusStatus.timestamp` is when delivery ended. Verified against 114 boluses in three
///   days of Mobi logs: that timestamp minus the delivery-start one equalled delivered volume over
///   the rate below to within -1.6…+1.1 s, across 3 s to 178 s of delivery. Both fields stamp the
///   pump event, not the reply — repeat reads of one unchanged state come back identical.
/// - The rate estimate, `deliveryStart + delivered / bolusSpeed`, is the fallback when there is no
///   usable pump timestamp, and the floor under one that is older than the delivery can have been.
///
/// The result is clamped to `detectedAt` and floored at the dose's start. The clamp matters: in
/// those logs the pump clock ran ~7-8 s ahead of the phone's (-3…+10 s), so without it a promptly
/// detected bolus would be dated into the future. Seconds of clock skew replace minutes of error.
enum BolusEndDate {
    // larger total deliveries are faster -- a 10.05u bolus is almost twice as fast as a 9.95u one
    static let bolusSpeedUnder10U = 1 / 28.745858684009523
    static let bolusSpeedOver10U = 1 / 11.200233479381131

    /// How long the pump spends accepting a bolus request before insulin starts moving. Exactly
    /// 15 s in every bolus across three days of pump logs.
    static let bolusInitiationDelay: TimeInterval = 15

    /// How long the pump takes to deliver `units`, at its nominal delivery rate.
    static func estimatedDuration(toBolus units: Double) -> TimeInterval {
        if units < 10 {
            units / bolusSpeedUnder10U
        } else {
            units / bolusSpeedOver10U
        }
    }

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
        let deliveryStart = deliveryStartDate ?? startDate.addingTimeInterval(bolusInitiationDelay)
        var candidate = deliveryStart

        if let deliveredUnits, deliveredUnits > 0 {
            candidate = deliveryStart.addingTimeInterval(estimatedDuration(toBolus: deliveredUnits))
        }

        if let pumpTimestamp, pumpTimestamp > candidate {
            candidate = pumpTimestamp
        }

        let doseStart = deliveryStartDate ?? startDate
        return max(doseStart, min(candidate, detectedAt))
    }
}
