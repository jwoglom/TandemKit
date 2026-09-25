import Foundation

/// History log entry recorded when a Dexcom G7 CGM session is stopped.
/// https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/CgmStopSessionG7HistoryLog.java
public class CgmStopSessionG7HistoryLog: HistoryLog {
    public static let typeId = 447

    public let currentTransmitterTime: UInt32
    public let sessionStartTime: UInt32
    public let sessionStopTime: UInt32
    public let stopSessionCode: Int
    public let sessionStopReason: Int
    public let sessionDuration: Int

    public required init(cargo: Data) {
        currentTransmitterTime = Bytes.readUint32(cargo, 10)
        sessionStartTime = Bytes.readUint32(cargo, 14)
        sessionStopTime = Bytes.readUint32(cargo, 18)
        stopSessionCode = Int(cargo[24])
        sessionStopReason = Int(cargo[23])
        sessionDuration = Int(cargo[22])
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        currentTransmitterTime: UInt32 = 0,
        sessionStartTime: UInt32 = 0,
        sessionStopTime: UInt32 = 0,
        stopSessionCode: Int = 0,
        sessionStopReason: Int = 0,
        sessionDuration: Int = 0
    ) {
        let payload = CgmStopSessionG7HistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            currentTransmitterTime: currentTransmitterTime,
            sessionStartTime: sessionStartTime,
            sessionStopTime: sessionStopTime,
            stopSessionCode: stopSessionCode,
            sessionStopReason: sessionStopReason,
            sessionDuration: sessionDuration
        )
        self.currentTransmitterTime = currentTransmitterTime
        self.sessionStartTime = sessionStartTime
        self.sessionStopTime = sessionStopTime
        self.stopSessionCode = stopSessionCode
        self.sessionStopReason = sessionStopReason
        self.sessionDuration = sessionDuration
        super.init(cargo: payload)
    }

    public convenience init(
        currentTransmitterTime: UInt32,
        sessionStartTime: UInt32,
        sessionStopTime: UInt32,
        stopSessionCode: Int,
        sessionStopReason: Int,
        sessionDuration: Int
    ) {
        self.init(
            pumpTimeSec: 0,
            sequenceNum: 0,
            currentTransmitterTime: currentTransmitterTime,
            sessionStartTime: sessionStartTime,
            sessionStopTime: sessionStopTime,
            stopSessionCode: stopSessionCode,
            sessionStopReason: sessionStopReason,
            sessionDuration: sessionDuration
        )
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        currentTransmitterTime: UInt32 = 0,
        sessionStartTime: UInt32 = 0,
        sessionStopTime: UInt32 = 0,
        stopSessionCode: Int = 0,
        sessionStopReason: Int = 0,
        sessionDuration: Int = 0
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId), // 447 = 0x01BF
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(currentTransmitterTime),
                Bytes.toUint32(sessionStartTime),
                Bytes.toUint32(sessionStopTime),
                Data([UInt8(sessionDuration & 0xFF)]),
                Data([UInt8(sessionStopReason & 0xFF)]),
                Data([UInt8(stopSessionCode & 0xFF)])
            )
        )
    }

    public var description: String {
        "CgmStopSessionG7HistoryLog(cargo=\(cargo.hexadecimalString), currentTransmitterTime=\(currentTransmitterTime), sessionStartTime=\(sessionStartTime), sessionStopTime=\(sessionStopTime), stopSessionCode=\(stopSessionCode), sessionStopReason=\(sessionStopReason), sessionDuration=\(sessionDuration))"
    }
}
