import Foundation

public enum QualifyingEvent: CaseIterable {
    case alert
    case alarm
    case reminder
    case malfunction
    case cgmAlert
    case homeScreenChange
    case pumpSuspend
    case pumpResume
    case timeChange
    case basalChange
    case bolusChange
    case iobChange
    case extendedBolusChange
    case profileChange
    case bg
    case cgmChange
    case battery
    case basalIQ
    case remainingInsulin
    case pumpCommunicationsSuspended
    case activeProfileSegmentChange
    case basalIQStatus
    case controlIQInfo
    case controlIQSleep
    case globalPumpSettings
    case snoozeStatus
    case pumpingStatus
    case pumpReset
    case heartbeat
    case bolusPermissionRevoked

    public var id: UInt32 {
        switch self {
        case .alert: return 1
        case .alarm: return 2
        case .reminder: return 4
        case .malfunction: return 8
        case .cgmAlert: return 16
        case .homeScreenChange: return 32
        case .pumpSuspend: return 64
        case .pumpResume: return 128
        case .timeChange: return 256
        case .basalChange: return 512
        case .bolusChange: return 1024
        case .iobChange: return 2048
        case .extendedBolusChange: return 4096
        case .profileChange: return 8192
        case .bg: return 16384
        case .cgmChange: return 32768
        case .battery: return 65536
        case .basalIQ: return 131_072
        case .remainingInsulin: return 262_144
        case .pumpCommunicationsSuspended: return 524_288
        case .activeProfileSegmentChange: return 1_048_576
        case .basalIQStatus: return 2_097_152
        case .controlIQInfo: return 4_194_304
        case .controlIQSleep: return 8_388_608
        case .globalPumpSettings: return 16_777_216
        case .snoozeStatus: return 33_554_432
        case .pumpingStatus: return 67_108_864
        case .pumpReset: return 134_217_728
        case .heartbeat: return 268_435_456
        case .bolusPermissionRevoked: return 2_147_483_648
        }
    }
    
    public static func fromRawBytes(_ raw: Data) -> Set<QualifyingEvent> {
        fromBitmask(Bytes.readUint32(raw, 0))
    }

    public static func fromBitmask(_ bitmask: UInt32) -> Set<QualifyingEvent> {
       var ret: Set<QualifyingEvent> = []
       for event in QualifyingEvent.allCases {
           if (bitmask & event.id) != 0 {
               ret.insert(event)
           }
       }
       return ret
   }

    /// Status requests that should be re-fetched when this event is raised, mirroring
    /// PumpX2's `QualifyingEvent.suggestedHandlers`. Version-dependent requests default to
    /// their V1 form (valid on all firmware); callers that know the negotiated API version
    /// can substitute via the corresponding request builders. Events with no stateless
    /// fetch (e.g. `.heartbeat`, or `.bolusPermissionRevoked` whose request needs a bolus
    /// id) return an empty list.
    public var suggestedHandlers: [() -> Message] {
        switch self {
        case .alert:
            return [{ AlertStatusRequest() }]
        case .alarm:
            return [{ AlarmStatusRequest() }, { HighestAamRequest() }, { ActiveAamBitsRequest(aamType: 2) }]
        case .reminder:
            return [{ ReminderStatusRequest() }]
        case .malfunction:
            return [{ MalfunctionStatusRequest() }, { HighestAamRequest() }, { ActiveAamBitsRequest(aamType: 4) }]
        case .cgmAlert:
            return [{ CGMAlertStatusRequest() }]
        case .homeScreenChange:
            return [{ HomeScreenMirrorRequest() }]
        case .pumpSuspend, .pumpResume:
            return [{ InsulinStatusRequest() }, { CurrentBasalStatusRequest() }]
        case .timeChange, .pumpReset:
            return [{ TimeSinceResetRequest() }]
        case .basalChange:
            return [{ CurrentBasalStatusRequest() }]
        case .bolusChange:
            return [{ CurrentBolusStatusRequest() }]
        case .iobChange:
            return [{ ControlIQIOBRequest() }]
        case .extendedBolusChange:
            return [{ ExtendedBolusStatusRequest() }]
        case .profileChange, .activeProfileSegmentChange:
            return [{ ProfileStatusRequest() }]
        case .bg:
            return [{ LastBGRequest() }]
        case .cgmChange:
            return [{ CGMStatusRequest() }, { CurrentEGVGuiDataRequest() }]
        case .battery:
            return [{ CurrentBatteryRequestBuilder.create(apiVersion: nil).0 }]
        case .basalIQ, .basalIQStatus:
            return [{ BasalIQStatusRequest() }]
        case .remainingInsulin:
            return [{ InsulinStatusRequest() }]
        case .controlIQInfo:
            return [{ ControlIQInfoV1Request() }]
        case .controlIQSleep:
            return [{ ControlIQSleepScheduleRequest() }]
        case .globalPumpSettings:
            return [
                { GlobalMaxBolusSettingsRequest() },
                { BasalLimitSettingsRequest() },
                { LocalizationRequest() },
                { PumpGlobalsRequest() },
                { PumpSettingsRequest() }
            ]
        case .pumpingStatus:
            return [{ LoadStatusRequest() }]
        case .pumpCommunicationsSuspended, .snoozeStatus, .heartbeat, .bolusPermissionRevoked:
            return []
        }
    }

    /// Builds the combined request list for a set of events, deduplicated by opcode + cargo
    /// so overlapping events (e.g. `.pumpSuspend` and `.pumpResume`) fetch each status once.
    /// Deduplication keys on cargo as well as opcode because distinct requests can share an
    /// opcode with different payloads (`ActiveAamBitsRequest(aamType: 2)` vs `(aamType: 4)`).
    public static func groupSuggestedHandlers(_ events: Set<QualifyingEvent>) -> [Message] {
        var seen: Set<RequestKey> = []
        var messages: [Message] = []

        // Iterate allCases (declaration order) rather than the unordered set so the
        // resulting request order is deterministic.
        for event in QualifyingEvent.allCases where events.contains(event) {
            for handler in event.suggestedHandlers {
                let message = handler()
                let key = RequestKey(opCode: type(of: message).props.opCode, cargo: message.cargo)
                if seen.insert(key).inserted {
                    messages.append(message)
                }
            }
        }

        return messages
    }

    private struct RequestKey: Hashable {
        let opCode: UInt8
        let cargo: Data
    }
}

/// Pump state that the qualifying-event suggested handlers depend on.
///
/// PumpX2 reads these out of its global `PumpStateSupplier`. TandemKit has no such global, so
/// the caller supplies them — `TandemPumpManager` fills them in from its own state.
public struct QualifyingEventContext {
    /// The API version the pump reported during pairing. When set, suggested handlers whose
    /// `minApi` is newer than it are dropped by `groupSuggestedHandlers`; when nil, nothing is
    /// filtered.
    public var apiVersion: ApiVersion?

    /// Whether the pump supports Control-IQ, which selects the insulin-on-board opcode.
    public var controlIQSupported: Bool

    /// The id of the bolus currently in progress, if one is known. `bolusPermissionRevoked`
    /// can only be followed up on when it is.
    public var inProgressBolusId: Int?

    public init(
        apiVersion: ApiVersion? = nil,
        controlIQSupported: Bool = false,
        inProgressBolusId: Int? = nil
    ) {
        self.apiVersion = apiVersion
        self.controlIQSupported = controlIQSupported
        self.inProgressBolusId = inProgressBolusId
    }
}

public extension QualifyingEvent {
    /// The requests that fetch more detail about this event, matching what the Tandem mobile
    /// app asks for. Mirrors PumpX2's `QualifyingEvent.getSuggestedHandlers()`.
    ///
    /// Events the app does not follow up on — `pumpCommunicationsSuspended`, `snoozeStatus`,
    /// `pumpReset`, `heartbeat` — return nothing, as does `bolusPermissionRevoked` when no
    /// in-progress bolus id is known.
    func suggestedHandlers(context: QualifyingEventContext = QualifyingEventContext()) -> [Message] {
        switch self {
        case .alert:
            return [AlertStatusRequest()]
        case .alarm:
            return [AlarmStatusRequest(), HighestAamRequest(), ActiveAamBitsRequest(aamType: 2)]
        case .reminder:
            return [ReminderStatusRequest()]
        case .malfunction:
            return [MalfunctionStatusRequest(), HighestAamRequest(), ActiveAamBitsRequest(aamType: 4)]
        case .cgmAlert:
            return [CGMAlertStatusRequest()]
        case .homeScreenChange:
            return [
                CurrentBasalStatusRequest(),
                CurrentEGVGuiDataRequest(),
                HomeScreenMirrorRequest(),
                context.controlIQInfoRequest
            ]
        case .pumpSuspend:
            return [InsulinStatusRequest(), context.iobRequest]
        case .pumpResume:
            return [
                InsulinStatusRequest(),
                context.iobRequest,
                CurrentEGVGuiDataRequest(),
                ProfileStatusRequest()
            ]
        case .timeChange:
            return [context.iobRequest, CGMStatusRequest(), TimeSinceResetRequest()]
        case .basalChange:
            return [
                context.iobRequest,
                HomeScreenMirrorRequest(),
                CurrentBasalStatusRequest(),
                TempRateRequest()
            ]
        case .bolusChange:
            return [
                CurrentBolusStatusRequest(),
                ExtendedBolusStatusRequest(),
                context.lastBolusStatusRequest
            ]
        case .iobChange:
            return [context.iobRequest]
        case .extendedBolusChange:
            return [ExtendedBolusStatusRequest(), context.lastBolusStatusRequest]
        case .profileChange:
            return [ProfileStatusRequest()]
        case .bg:
            return [LastBGRequest()]
        case .cgmChange:
            return [CGMStatusRequest(), CurrentEGVGuiDataRequest(), HomeScreenMirrorRequest()]
        case .battery:
            return [context.currentBatteryRequest]
        case .basalIQ:
            return [BasalIQSettingsRequest()]
        case .remainingInsulin:
            return [InsulinStatusRequest()]
        case .pumpCommunicationsSuspended:
            return []
        case .activeProfileSegmentChange:
            return [ProfileStatusRequest()]
        case .basalIQStatus:
            return [BasalIQSettingsRequest(), BasalIQStatusRequest()]
        case .controlIQInfo:
            return [context.iobRequest, context.controlIQInfoRequest, ControlIQSleepScheduleRequest()]
        case .controlIQSleep:
            return [ControlIQSleepScheduleRequest()]
        case .globalPumpSettings:
            return [
                GlobalMaxBolusSettingsRequest(),
                BasalLimitSettingsRequest(),
                LocalizationRequest(),
                PumpGlobalsRequest(),
                PumpSettingsRequest()
            ]
        case .snoozeStatus:
            return []
        case .pumpingStatus:
            return [LoadStatusRequest()]
        case .pumpReset:
            return []
        case .heartbeat:
            return []
        case .bolusPermissionRevoked:
            guard let bolusId = context.inProgressBolusId else {
                return []
            }
            return [BolusPermissionChangeReasonRequest(bolusId: bolusId)]
        }
    }

    /// The combined suggested handlers for a set of events, deduplicated and filtered to what
    /// the pump's API version supports. Mirrors PumpX2's `groupSuggestedHandlers`.
    ///
    /// Events share requests — `homeScreenChange` and `basalChange` both want the current basal
    /// status — so a batch of events must not send the same request twice. Requests are returned
    /// in qualifying-event bit order, then in per-event order, so the sequence is stable.
    static func groupSuggestedHandlers(
        _ events: Set<QualifyingEvent>,
        context: QualifyingEventContext = QualifyingEventContext()
    ) -> [Message] {
        var seen: Set<String> = []
        var requests: [Message] = []

        // Iterate over allCases rather than the (unordered) set so the order is deterministic.
        for event in QualifyingEvent.allCases where events.contains(event) {
            for request in event.suggestedHandlers(context: context) {
                // Two requests of the same type can still differ — ActiveAamBitsRequest carries
                // the AAM type it asks about — so the cargo is part of the identity.
                let key = "\(type(of: request))|\(request.cargo.hexadecimalString)"
                guard !seen.contains(key) else { continue }
                guard supportsApiVersion(request, context.apiVersion) else { continue }
                seen.insert(key)
                requests.append(request)
            }
        }

        return requests
    }

    /// Whether the pump's negotiated API version is new enough to support the given request.
    ///
    /// Deliberately not `MessageProps.isSupported(pumpModel:apiVersion:)`: that also gates on the
    /// pump model and answers false when either is still unknown, which would filter out every
    /// suggested handler before the first sync has identified the pump. PumpX2 checks `minApi`
    /// alone here, and an unknown API version filters nothing.
    private static func supportsApiVersion(_ request: Message, _ apiVersion: ApiVersion?) -> Bool {
        guard let apiVersion = apiVersion else {
            return true
        }
        return !type(of: request).props.minApi.value.greaterThan(apiVersion)
    }
}

private extension QualifyingEventContext {
    var iobRequest: Message {
        IOBRequestBuilder.create(controlIQSupported: controlIQSupported).0
    }

    var controlIQInfoRequest: Message {
        ControlIQInfoRequestBuilder.create(apiVersion: apiVersion).0
    }

    var lastBolusStatusRequest: Message {
        LastBolusRequestBuilder.create(apiVersion: apiVersion).0
    }

    var currentBatteryRequest: Message {
        CurrentBatteryRequestBuilder.create(apiVersion: apiVersion).0
    }
}
