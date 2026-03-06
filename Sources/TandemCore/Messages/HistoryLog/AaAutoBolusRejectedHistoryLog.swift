import Foundation

public class AaAutoBolusRejectedHistoryLog: HistoryLog {
    public static let typeId = 288

    public required init(cargo: Data) {
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32) {
        super.init(cargo: AaAutoBolusRejectedHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum))
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

    public var description: String {
        "AaAutoBolusRejectedHistoryLog(cargo=\(cargo.hexadecimalString))"
    }
}
