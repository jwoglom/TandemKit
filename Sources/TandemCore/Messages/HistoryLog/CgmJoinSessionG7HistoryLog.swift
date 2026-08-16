import Foundation

/// History log entry recorded when a Dexcom G7 CGM session is joined.
/// https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/CgmJoinSessionG7HistoryLog.java
public class CgmJoinSessionG7HistoryLog: HistoryLog {
    public static let typeId = 394

    public let cgmTimestamp: UInt32
    public let sessionSignature: UInt32

    public required init(cargo: Data) {
        cgmTimestamp = Bytes.readUint32(cargo, 10)
        sessionSignature = Bytes.readUint32(cargo, 14)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, cgmTimestamp: UInt32 = 0, sessionSignature: UInt32 = 0) {
        let payload = CgmJoinSessionG7HistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            cgmTimestamp: cgmTimestamp,
            sessionSignature: sessionSignature
        )
        self.cgmTimestamp = cgmTimestamp
        self.sessionSignature = sessionSignature
        super.init(cargo: payload)
    }

    public convenience init(cgmTimestamp: UInt32, sessionSignature: UInt32) {
        self.init(pumpTimeSec: 0, sequenceNum: 0, cgmTimestamp: cgmTimestamp, sessionSignature: sessionSignature)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, cgmTimestamp: UInt32 = 0, sessionSignature: UInt32 = 0) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(cgmTimestamp),
                Bytes.toUint32(sessionSignature)
            )
        )
    }

    public var description: String {
        "CgmJoinSessionG7HistoryLog(cargo=\(cargo.hexadecimalString), cgmTimestamp=\(cgmTimestamp), sessionSignature=\(sessionSignature))"
    }
}
