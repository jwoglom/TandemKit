import Foundation

/// FreeStyle Libre 3 CGM session stop.
///
/// Mirrors pumpX2's `CgmStopSessionFsl3HistoryLog`.
public class CgmStopSessionFsl3HistoryLog: HistoryLog {
    public static let typeId = 486

    /// Session start time, in seconds since the Tandem epoch.
    public let sessionStartTime: UInt32
    /// Session stop time, in seconds since the Tandem epoch.
    public let sessionStopTime: UInt32
    /// Session duration, in days.
    public let sessionDuration: Int
    /// Reason the session was stopped (values not documented by Tandem).
    public let sessionStopReason: Int

    public required init(cargo: Data) {
        sessionStartTime = Bytes.readUint32(cargo, 10)
        sessionStopTime = Bytes.readUint32(cargo, 14)
        sessionDuration = Int(cargo[cargo.startIndex + 18])
        sessionStopReason = Int(cargo[cargo.startIndex + 19])
        super.init(cargo: cargo)
    }

    public convenience init(pumpTimeSec: UInt32, sequenceNum: UInt32) {
        self.init(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, sessionStartTime: 0, sessionStopTime: 0, sessionDuration: 0, sessionStopReason: 0)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        sessionStartTime: UInt32,
        sessionStopTime: UInt32,
        sessionDuration: Int,
        sessionStopReason: Int
    ) {
        let payload = CgmStopSessionFsl3HistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            sessionStartTime: sessionStartTime,
            sessionStopTime: sessionStopTime,
            sessionDuration: sessionDuration,
            sessionStopReason: sessionStopReason
        )
        self.sessionStartTime = sessionStartTime
        self.sessionStopTime = sessionStopTime
        self.sessionDuration = sessionDuration
        self.sessionStopReason = sessionStopReason
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32) -> Data {
        buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, sessionStartTime: 0, sessionStopTime: 0, sessionDuration: 0, sessionStopReason: 0)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        sessionStartTime: UInt32,
        sessionStopTime: UInt32,
        sessionDuration: Int,
        sessionStopReason: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(sessionStartTime),
                Bytes.toUint32(sessionStopTime),
                Data([UInt8(sessionDuration & 0xFF)]),
                Data([UInt8(sessionStopReason & 0xFF)])
            )
        )
    }

    override public var description: String {
        "CgmStopSessionFsl3HistoryLog(cargo=\(cargo.hexadecimalString), sessionStartTime=\(sessionStartTime), sessionStopTime=\(sessionStopTime), sessionDuration=\(sessionDuration), sessionStopReason=\(sessionStopReason))"
    }
}
