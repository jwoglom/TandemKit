import Foundation

/// History log entry recorded when a GX (Dexcom G6/G7) CGM session is started.
/// https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/CgmStartSessionHistoryLog.java
public class CgmStartSessionHistoryLog: HistoryLog {
    public static let typeId = 212

    /// The current transmitter time, in seconds.
    public let currentTransmitterTime: UInt32
    /// The session start time, in seconds.
    public let sessionStartTime: UInt32
    /// The session duration, in days.
    public let sessionDuration: Int

    public required init(cargo: Data) {
        currentTransmitterTime = Bytes.readUint32(cargo, 10)
        sessionStartTime = Bytes.readUint32(cargo, 14)
        sessionDuration = Int(cargo[22])
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        currentTransmitterTime: UInt32 = 0,
        sessionStartTime: UInt32 = 0,
        sessionDuration: Int = 0
    ) {
        let payload = CgmStartSessionHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            currentTransmitterTime: currentTransmitterTime,
            sessionStartTime: sessionStartTime,
            sessionDuration: sessionDuration
        )
        self.currentTransmitterTime = currentTransmitterTime
        self.sessionStartTime = sessionStartTime
        self.sessionDuration = sessionDuration
        super.init(cargo: payload)
    }

    public convenience init(currentTransmitterTime: UInt32, sessionStartTime: UInt32, sessionDuration: Int) {
        self.init(
            pumpTimeSec: 0,
            sequenceNum: 0,
            currentTransmitterTime: currentTransmitterTime,
            sessionStartTime: sessionStartTime,
            sessionDuration: sessionDuration
        )
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        currentTransmitterTime: UInt32 = 0,
        sessionStartTime: UInt32 = 0,
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
                Data([UInt8(sessionDuration & 0xFF)])
            )
        )
    }

    public var description: String {
        "CgmStartSessionHistoryLog(cargo=\(cargo.hexadecimalString), currentTransmitterTime=\(currentTransmitterTime), sessionStartTime=\(sessionStartTime), sessionDuration=\(sessionDuration))"
    }
}
