import Foundation

public class ConfirmCartridgeFilledHistoryLog: HistoryLog {
    public static let typeId = 41

    public required init(cargo: Data) {
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32) {
        super.init(cargo: ConfirmCartridgeFilledHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum))
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
        "ConfirmCartridgeFilledHistoryLog(cargo=\(cargo.hexadecimalString))"
    }
}
