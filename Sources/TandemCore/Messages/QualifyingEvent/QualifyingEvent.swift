//
//  QualifyingEvent.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Swift representation of PumpX2's QualifyingEvent enumeration.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/qualifyingEvent/QualifyingEvent.java
//
import Foundation

/// Message factories used to fetch additional details for a qualifying event.
public typealias MessageFactory = () -> Message

/// A list of events which can be emitted by the pump, along with suggested
/// request messages that may be sent to obtain further details.
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
    case suspendComm
    case activeSegmentChange
    case basalIQStatus
    case controlIQInfo
    case controlIQSleep
    case bolusPermissionRevoked

    /// Identifier used in bitmasks from the pump.
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
        case .basalIQ: return 131072
        case .remainingInsulin: return 262144
        case .suspendComm: return 524288
        case .activeSegmentChange: return 1048576
        case .basalIQStatus: return 2097152
        case .controlIQInfo: return 4194304
        case .controlIQSleep: return 8388608
        case .bolusPermissionRevoked: return 2147483648
        }
    }

    /// Suggested request messages to handle this event. These mirror the
    /// behavior of Tandem's mobile applications which, upon receiving a
    /// qualifying event, issue follow-up requests for additional context.
    ///
    /// The factories return concrete `Message` types which may be dispatched
    /// to the pump to retrieve those details.
    @MainActor
    public var suggestedHandlers: [MessageFactory] {
        switch self {
        case .alert:
            return [{ AlertStatusRequest() }]
        case .alarm:
            return [{ AlarmStatusRequest() }]
        case .reminder:
            return [{ ReminderStatusRequest() }]
        case .malfunction:
            return [{ MalfunctionStatusRequest() }]
        case .cgmAlert:
            return [{ CGMAlertStatusRequest() }]
        case .homeScreenChange:
            return [
                { CurrentBasalStatusRequest() },
                { CurrentEGVGuiDataRequest() },
                { HomeScreenMirrorRequest() },
                { ControlIQInfoRequestBuilder.create(apiVersion: PumpStateSupplier.pumpApiVersion?() ?? KnownApiVersion.apiV2_1.value) }
            ]
        case .pumpSuspend:
            return [
                { InsulinStatusRequest() },
                { IOBRequestBuilder.create(controlIQ: PumpStateSupplier.controlIQSupported()) }
            ]
        case .pumpResume:
            return [
                { InsulinStatusRequest() },
                { IOBRequestBuilder.create(controlIQ: PumpStateSupplier.controlIQSupported()) },
                { CurrentEGVGuiDataRequest() },
                { ProfileStatusRequest() }
            ]
        case .timeChange:
            return [
                { IOBRequestBuilder.create(controlIQ: PumpStateSupplier.controlIQSupported()) },
                { CGMStatusRequest() },
                { TimeSinceResetRequest() }
            ]
        case .basalChange:
            return [
                { IOBRequestBuilder.create(controlIQ: PumpStateSupplier.controlIQSupported()) },
                { HomeScreenMirrorRequest() },
                { CurrentBasalStatusRequest() },
                { TempRateRequest() }
            ]
        case .bolusChange:
            return [
                { CurrentBolusStatusRequest() },
                { ExtendedBolusStatusRequest() },
                { LastBolusStatusRequestBuilder.create(apiVersion: PumpStateSupplier.pumpApiVersion?() ?? KnownApiVersion.apiV2_1.value) }
            ]
        case .iobChange:
            return [{ IOBRequestBuilder.create(controlIQ: PumpStateSupplier.controlIQSupported()) }]
        case .extendedBolusChange:
            return [
                { ExtendedBolusStatusRequest() },
                { LastBolusStatusRequestBuilder.create(apiVersion: PumpStateSupplier.pumpApiVersion?() ?? KnownApiVersion.apiV2_1.value) }
            ]
        case .profileChange:
            return [{ ProfileStatusRequest() }]
        case .bg:
            return [{ LastBGRequest() }]
        case .cgmChange:
            return [
                { CGMStatusRequest() },
                { CurrentEGVGuiDataRequest() },
                { HomeScreenMirrorRequest() }
            ]
        case .battery:
            return [{ CurrentBatteryRequestBuilder.create(apiVersion: PumpStateSupplier.pumpApiVersion?() ?? KnownApiVersion.apiV2_1.value) }]
        case .basalIQ:
            return [{ BasalIQSettingsRequest() }]
        case .remainingInsulin:
            return [{ InsulinStatusRequest() }]
        case .suspendComm:
            return []
        case .activeSegmentChange:
            return [{ ProfileStatusRequest() }]
        case .basalIQStatus:
            return [{ BasalIQSettingsRequest() }, { BasalIQStatusRequest() }]
        case .controlIQInfo:
            return [
                { IOBRequestBuilder.create(controlIQ: PumpStateSupplier.controlIQSupported()) },
                { ControlIQInfoRequestBuilder.create(apiVersion: PumpStateSupplier.pumpApiVersion?() ?? KnownApiVersion.apiV2_1.value) },
                { ControlIQSleepScheduleRequest() }
            ]
        case .controlIQSleep:
            return [{ ControlIQSleepScheduleRequest() }]
        case .bolusPermissionRevoked:
            return []
        }
    }

    /// Convert a bitmask into a set of QualifyingEvents.
    public static func fromBitmask(_ bitmask: UInt32) -> Set<QualifyingEvent> {
        var ret: Set<QualifyingEvent> = []
        for event in QualifyingEvent.allCases {
            if (bitmask & event.id) != 0 {
                ret.insert(event)
            }
        }
        return ret
    }

    /// Parse a 4-byte little-endian bitmask from raw Bluetooth data.
    public static func fromRawBytes(_ raw: Data) -> Set<QualifyingEvent> {
        return fromBitmask(Bytes.readUint32(raw, 0))
    }

    /// Return suggested request messages for a set of events.
    @MainActor
    public static func groupSuggestedHandlers(_ events: Set<QualifyingEvent>) -> [Message] {
        var messages: [Message] = []
        for e in events {
            for factory in e.suggestedHandlers {
                messages.append(factory())
            }
        }
        // remove duplicates by opcode
        var seen: Set<UInt8> = []
        messages = messages.filter { msg in
            let op = type(of: msg).props.opCode
            if seen.contains(op) { return false }
            seen.insert(op)
            return true
        }
        return messages
    }

    /// Construct a bitmask from multiple events.
    public static func toBitmask(_ events: [QualifyingEvent]) -> UInt32 {
        return events.reduce(0) { $0 | $1.id }
    }
}

