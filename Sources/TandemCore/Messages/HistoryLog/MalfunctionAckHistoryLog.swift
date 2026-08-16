import Foundation

public class MalfunctionAckHistoryLog: HistoryLog {
    public static let typeId = 7

    public let malfId: UInt32

    public required init(cargo: Data) {
        malfId = Bytes.readUint32(cargo, 10)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, malfId: UInt32) {
        let payload = MalfunctionAckHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, malfId: malfId)
        self.malfId = malfId
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, malfId: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(malfId)
            )
        )
    }

    public var description: String {
        "MalfunctionAckHistoryLog(cargo=\(cargo.hexadecimalString), malfId=\(malfId))"
    }
}
