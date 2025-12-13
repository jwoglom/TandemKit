import Foundation

/// History log marker for CGM stop session events (Gx).
public class CgmStopSessionHistoryLog: HistoryLog {
    public static let typeId = 214

    public required init(cargo: Data) {
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32) {
        let payload = CgmStopSessionHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum)
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum)
            )
        )
    }
}

public extension CgmStopSessionHistoryLog {
    var description: String {
        "CgmStopSessionHistoryLog(cargo=\(cargo.hexadecimalString))"
    }
}
