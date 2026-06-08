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
    
    private static func fromBitmask(_ bitmask: UInt32) -> Set<QualifyingEvent> {
       var ret: Set<QualifyingEvent> = []
       for event in QualifyingEvent.allCases {
           if (bitmask & event.id) != 0 {
               ret.insert(event)
           }
       }
       return ret
   }
}
