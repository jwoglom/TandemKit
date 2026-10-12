import Foundation

/// The status fetches that service a qualifying event.
///
/// PumpX2 answers a qualifying event by dispatching `QualifyingEvent.groupSuggestedHandlers` —
/// the batch of status requests the Tandem app sends — and letting its per-message callbacks
/// pick the responses up wherever they land. TandemKit has no such generic response router:
/// each `fetch…` on `TandemPumpManager` both issues its request and applies the response to
/// `state`. So rather than keeping a second event table that could drift from the ported one,
/// the suggested handlers stay authoritative and each request is mapped to the fetch that
/// serves it.
///
/// A request that maps to no fetch is not sent. Nothing in the driver consumes CGM/EGV, home
/// screen mirror, Basal-IQ, temp rate, localization, load status or bolus permission change
/// reason today, and issuing those would spend a BLE round trip on a response that gets
/// discarded.
enum QualifyingEventFetch: CaseIterable {
    /// The whole alert/alarm/reminder/CGM-alert/malfunction bundle (`fetchNotifications`).
    case notifications
    case controlIQStatus
    case basalStatus
    case bolusStatus
    case insulinDuration
    case insulinOnBoard
    case reservoirStatus
    case batteryStatus
    case deliveryLimits
    case globalPumpSettings
    case timeSinceReset

    /// The fetch that issues and consumes `request`, or nil when the driver has no use for it.
    ///
    /// Several requests share a fetch: the notification bundle covers every alert/alarm/AAM
    /// request in one reload, and the delivery-limits fetch reads the basal and bolus ceilings
    /// together.
    static func fetch(servicing request: Message) -> QualifyingEventFetch? {
        switch request {
        case is AlertStatusRequest,
             is AlarmStatusRequest,
             is ReminderStatusRequest,
             is CGMAlertStatusRequest,
             is MalfunctionStatusRequest,
             is HighestAamRequest,
             is ActiveAamBitsRequest:
            return .notifications
        case is ControlIQInfoV1Request, is ControlIQInfoV2Request:
            return .controlIQStatus
        case is CurrentBasalStatusRequest:
            return .basalStatus
        case is CurrentBolusStatusRequest:
            return .bolusStatus
        case is ProfileStatusRequest:
            return .insulinDuration
        case is ControlIQIOBRequest:
            return .insulinOnBoard
        case is InsulinStatusRequest:
            return .reservoirStatus
        case is CurrentBatteryV1Request, is CurrentBatteryV2Request:
            return .batteryStatus
        case is BasalLimitSettingsRequest, is GlobalMaxBolusSettingsRequest:
            return .deliveryLimits
        case is PumpGlobalsRequest:
            return .globalPumpSettings
        case is TimeSinceResetRequest:
            return .timeSinceReset
        default:
            return nil
        }
    }

    /// The fetches that service a batch of events, deduplicated and returned in `allCases`
    /// order so a batch runs each fetch once, in a predictable sequence.
    static func fetches(
        for events: Set<QualifyingEvent>,
        context: QualifyingEventContext
    ) -> [QualifyingEventFetch] {
        var needed = Set(
            QualifyingEvent.groupSuggestedHandlers(events, context: context)
                .compactMap(fetch(servicing:))
        )

        // One deliberate addition to PumpX2's table, in the safety-positive direction for a Loop
        // driver: PumpX2 asks only for insulin status when delivery is suspended or resumed, but
        // the basal read is what emits the suspend/resume dose to LoopKit, and the pump does not
        // always pair those events with a basalChange.
        if !events.isDisjoint(with: [.pumpSuspend, .pumpResume]) {
            needed.insert(.basalStatus)
        }

        // Also not in PumpX2's table: an occlusion, empty cartridge, auto-off or malfunction stops
        // delivery, and whether the pump raises pumpSuspend with it is unconfirmed on hardware.
        if !events.isDisjoint(with: [.alarm, .malfunction]) {
            needed.insert(.basalStatus)
        }

        // Also not in PumpX2's table: after a profile change on the pump, read basal status now so
        // `verifyDeliveredBasalRate` catches a mismatch without waiting for the next sync.
        if !events.isDisjoint(with: [.profileChange, .activeProfileSegmentChange]) {
            needed.insert(.basalStatus)
        }

        return allCases.filter { needed.contains($0) }
    }
}
