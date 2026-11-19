import Foundation

/// FreeStyle Libre 3 CGM session join.
///
/// Mirrors pumpX2's `CgmJoinSessionFsl3HistoryLog`.
public class CgmJoinSessionFsl3HistoryLog: HistoryLog {
    public static let typeId = 477

    /// Session start time, in seconds since the Tandem epoch.
    public let sessionStartTime: UInt32
    /// Session join time, in seconds since the Tandem epoch.
    public let sessionJoinTime: UInt32
    /// Session duration, in days.
    public let sessionDuration: Int
    /// Reason the session was joined (values not documented by Tandem).
    public let sessionJoinReason: Int
    /// Session duration, in seconds.
    public let sessionDurationSecs: UInt32

    public required init(cargo: Data) {
        sessionStartTime = Bytes.readUint32(cargo, 10)
        sessionJoinTime = Bytes.readUint32(cargo, 14)
        sessionDuration = Int(cargo[cargo.startIndex + 18])
        sessionJoinReason = Int(cargo[cargo.startIndex + 19])
        sessionDurationSecs = Bytes.readUint32(cargo, 22)
        super.init(cargo: cargo)
    }

    public convenience init(pumpTimeSec: UInt32, sequenceNum: UInt32) {
        self.init(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, sessionStartTime: 0, sessionJoinTime: 0, sessionDuration: 0, sessionJoinReason: 0, sessionDurationSecs: 0)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        sessionStartTime: UInt32,
        sessionJoinTime: UInt32,
        sessionDuration: Int,
        sessionJoinReason: Int,
        sessionDurationSecs: UInt32
    ) {
        let payload = CgmJoinSessionFsl3HistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            sessionStartTime: sessionStartTime,
            sessionJoinTime: sessionJoinTime,
            sessionDuration: sessionDuration,
            sessionJoinReason: sessionJoinReason,
            sessionDurationSecs: sessionDurationSecs
        )
        self.sessionStartTime = sessionStartTime
        self.sessionJoinTime = sessionJoinTime
        self.sessionDuration = sessionDuration
        self.sessionJoinReason = sessionJoinReason
        self.sessionDurationSecs = sessionDurationSecs
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32) -> Data {
        buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, sessionStartTime: 0, sessionJoinTime: 0, sessionDuration: 0, sessionJoinReason: 0, sessionDurationSecs: 0)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        sessionStartTime: UInt32,
        sessionJoinTime: UInt32,
        sessionDuration: Int,
        sessionJoinReason: Int,
        sessionDurationSecs: UInt32
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(sessionStartTime),
                Bytes.toUint32(sessionJoinTime),
                Data([UInt8(sessionDuration & 0xFF)]),
                Data([UInt8(sessionJoinReason & 0xFF)]),
                Data([0, 0]),
                Bytes.toUint32(sessionDurationSecs)
            )
        )
    }

    override public var description: String {
        "CgmJoinSessionFsl3HistoryLog(cargo=\(cargo.hexadecimalString), sessionStartTime=\(sessionStartTime), sessionJoinTime=\(sessionJoinTime), sessionDuration=\(sessionDuration), sessionJoinReason=\(sessionJoinReason), sessionDurationSecs=\(sessionDurationSecs))"
    }
}
