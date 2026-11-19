import Foundation

/// FreeStyle Libre 2 CGM session start.
///
/// Mirrors pumpX2's `CgmStartSessionFsl2HistoryLog`.
public class CgmStartSessionFsl2HistoryLog: HistoryLog {
    public static let typeId = 404

    /// Session start time, in seconds since the Tandem epoch.
    public let sessionStartTime: UInt32
    /// Session duration, in days.
    public let sessionDuration: Int

    public required init(cargo: Data) {
        sessionStartTime = Bytes.readUint32(cargo, 10)
        sessionDuration = Int(cargo[cargo.startIndex + 14])
        super.init(cargo: cargo)
    }

    public convenience init(pumpTimeSec: UInt32, sequenceNum: UInt32) {
        self.init(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, sessionStartTime: 0, sessionDuration: 0)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        sessionStartTime: UInt32,
        sessionDuration: Int
    ) {
        let payload = CgmStartSessionFsl2HistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            sessionStartTime: sessionStartTime,
            sessionDuration: sessionDuration
        )
        self.sessionStartTime = sessionStartTime
        self.sessionDuration = sessionDuration
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32) -> Data {
        buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, sessionStartTime: 0, sessionDuration: 0)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        sessionStartTime: UInt32,
        sessionDuration: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(sessionStartTime),
                Data([UInt8(sessionDuration & 0xFF)])
            )
        )
    }

    override public var description: String {
        "CgmStartSessionFsl2HistoryLog(cargo=\(cargo.hexadecimalString), sessionStartTime=\(sessionStartTime), sessionDuration=\(sessionDuration))"
    }
}
