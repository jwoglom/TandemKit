import Foundation

/// History log entry recorded when a GX (Dexcom G6/G7) CGM session is joined.
/// https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/CgmJoinSessionHistoryLog.java
public class CgmJoinSessionHistoryLog: HistoryLog {
    public static let typeId = 213

    /// The current transmitter time, in seconds.
    public let currentTransmitterTime: UInt32
    /// The session start time, in seconds.
    public let sessionStartTime: UInt32
    public let sessionJoinReasonRaw: Int
    /// The session duration, in days.
    public let sessionDuration: Int

    public required init(cargo: Data) {
        currentTransmitterTime = Bytes.readUint32(cargo, 10)
        sessionStartTime = Bytes.readUint32(cargo, 14)
        sessionJoinReasonRaw = Int(cargo[23])
        sessionDuration = Int(cargo[22])
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        currentTransmitterTime: UInt32 = 0,
        sessionStartTime: UInt32 = 0,
        sessionJoinReasonRaw: Int = 0,
        sessionDuration: Int = 0
    ) {
        let payload = CgmJoinSessionHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            currentTransmitterTime: currentTransmitterTime,
            sessionStartTime: sessionStartTime,
            sessionJoinReasonRaw: sessionJoinReasonRaw,
            sessionDuration: sessionDuration
        )
        self.currentTransmitterTime = currentTransmitterTime
        self.sessionStartTime = sessionStartTime
        self.sessionJoinReasonRaw = sessionJoinReasonRaw
        self.sessionDuration = sessionDuration
        super.init(cargo: payload)
    }

    public convenience init(currentTransmitterTime: UInt32, sessionStartTime: UInt32, sessionJoinReasonRaw: Int, sessionDuration: Int) {
        self.init(
            pumpTimeSec: 0,
            sequenceNum: 0,
            currentTransmitterTime: currentTransmitterTime,
            sessionStartTime: sessionStartTime,
            sessionJoinReasonRaw: sessionJoinReasonRaw,
            sessionDuration: sessionDuration
        )
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        currentTransmitterTime: UInt32 = 0,
        sessionStartTime: UInt32 = 0,
        sessionJoinReasonRaw: Int = 0,
        sessionDuration: Int = 0
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(currentTransmitterTime),
                Bytes.toUint32(sessionStartTime),
                Data([0, 0, 0, 0]),
                Data([UInt8(sessionDuration & 0xFF)]),
                Data([UInt8(sessionJoinReasonRaw & 0xFF)])
            )
        )
    }

    public enum SessionJoinReason: Int {
        case DEXBLES_REASON_USER = 0
        case DEXBLES_REASON_UNKNOWN = 1
        case DEXBLES_REASON_TX_END_OF_LIFE = 3
        case DEXBLES_REASON_TRANSMITTER_ERROR = 4
        case DEXBLES_REASON_SESSION_STOP_SUCCESS = 5
        case DEXBLES_REASON_TRANSMITTER_NOT_IN_SESSION = 6
        case DEXBLES_REASON_NEW_SESSION_STARTED_SUCCESS = 8
        case DEXBLES_REASON_SESSION_STARTED_IN_PROGRESS = 9
        case DEXBLES_REASON_TRANSMITTER_IN_SESSION = 10
        case DEXBLES_REASON_BLESTACK_INVALID = 11
        case DEXBLES_REASON_NEW_AUTOCAL_SESSION_STARTED_SUCCESS = 12
        /// Tandem schema name: DEXBLES_REASON_AUTOCAL_SESSION_IN_PROGRESS
        case DEXBLES_REASON_NO_AUTOCAL_SESSION_IN_PROGRESS = 13
        case DEXBLES_REASON_STALE_START_CMD = 21
        case DEXBLES_REASON_STALE_STOP_CMD = 22

        public static func fromId(_ id: Int) -> SessionJoinReason? {
            SessionJoinReason(rawValue: id)
        }
    }

    public var sessionJoinReason: SessionJoinReason? {
        SessionJoinReason.fromId(sessionJoinReasonRaw)
    }

    public var description: String {
        "CgmJoinSessionHistoryLog(cargo=\(cargo.hexadecimalString), currentTransmitterTime=\(currentTransmitterTime), sessionStartTime=\(sessionStartTime), sessionJoinReasonRaw=\(sessionJoinReasonRaw), sessionDuration=\(sessionDuration))"
    }
}
