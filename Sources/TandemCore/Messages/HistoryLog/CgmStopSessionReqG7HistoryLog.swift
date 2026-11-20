import Foundation

public class CgmStopSessionReqG7HistoryLog: HistoryLog {
    public static let typeId = 443

    public required init(cargo: Data) {
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32) {
        super.init(cargo: CgmStopSessionReqG7HistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum))
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum)
            )
        )
    }

    override public var description: String {
        "CgmStopSessionReqG7HistoryLog(cargo=\(cargo.hexadecimalString))"
    }
}
