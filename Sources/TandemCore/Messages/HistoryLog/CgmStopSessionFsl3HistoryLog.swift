import Foundation

/// History log marker for FreeStyle Libre 3 CGM stop session events.
public class CgmStopSessionFsl3HistoryLog: HistoryLog {
    public static let typeId = 486

    public required init(cargo: Data) {
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32) {
        let payload = CgmStopSessionFsl3HistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum)
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

public extension CgmStopSessionFsl3HistoryLog {
    var description: String {
        "CgmStopSessionFsl3HistoryLog(cargo=\(cargo.hexadecimalString))"
    }
}
