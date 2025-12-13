import Foundation

/// History log marker for CGM start session events (Gx).
public class CgmStartSessionHistoryLog: HistoryLog {
    public static let typeId = 212

    public required init(cargo: Data) {
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32) {
        let payload = CgmStartSessionHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum)
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

public extension CgmStartSessionHistoryLog {
    var description: String {
        "CgmStartSessionHistoryLog(cargo=\(cargo.hexadecimalString))"
    }
}
