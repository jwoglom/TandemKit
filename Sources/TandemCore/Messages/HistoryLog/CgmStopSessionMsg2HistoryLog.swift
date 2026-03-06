import Foundation

public class CgmStopSessionMsg2HistoryLog: HistoryLog {
    public static let typeId = 163

    public required init(cargo: Data) {
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32) {
        super.init(cargo: CgmStopSessionMsg2HistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum))
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

    public var description: String {
        "CgmStopSessionMsg2HistoryLog(cargo=\(cargo.hexadecimalString))"
    }
}
