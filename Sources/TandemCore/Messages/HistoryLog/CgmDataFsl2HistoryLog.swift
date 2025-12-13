import Foundation

/// History log marker for FreeStyle Libre 2 CGM data packets.
public class CgmDataFsl2HistoryLog: HistoryLog {
    public static let typeId = 372

    public required init(cargo: Data) {
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32) {
        let payload = CgmDataFsl2HistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum)
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), UInt8((typeId >> 8) & 0xFF)]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum)
            )
        )
    }
}

public extension CgmDataFsl2HistoryLog {
    var description: String {
        "CgmDataFsl2HistoryLog(cargo=\(cargo.hexadecimalString))"
    }
}
